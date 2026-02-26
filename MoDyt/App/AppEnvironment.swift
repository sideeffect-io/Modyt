import Foundation
import DeltaDoreClient

struct AppEnvironment: Sendable {
    let repository: DeviceDatasource
    let groupRepository: GroupDatasource
    let newShutterRepository: ShutterRepository
    let sendDeviceCommand: @Sendable (String, String, PayloadValue) async -> Void
    let log: @Sendable (String) -> Void

    static func live() -> AppEnvironment {
        let databaseURL = AppDirectories.databaseURL()
        let now: @Sendable () -> Date = Date.init
        let log: @Sendable (String) -> Void = { message in
            #if DEBUG
            print("[MoDyt] \(message)")
            #endif
        }
        let dependencyBag = DependencyBag.live(
            databasePath: databaseURL.path,
            now: now,
            log: log
        )
        let client = dependencyBag.client
        let repository = DeviceDatasource(databasePath: databaseURL.path, log: log)
        let groupRepository = GroupDatasource(
            databasePath: databaseURL.path,
            deviceRepository: repository,
            log: log
        )
        let newShutterRepository = ShutterRepository(
            databasePath: databaseURL.path,
            deviceRepository: repository,
            log: log
        )
        let commandTransactionIdGenerator = CommandTransactionIdGenerator(now: now)

        let sendDeviceCommand: @Sendable (String, String, PayloadValue) async -> Void = { uniqueId, key, value in
            if GroupRecord.isGroupUniqueId(uniqueId) {
                let fanOut = await groupRepository.fanOutCommands(
                    uniqueId: uniqueId,
                    key: key,
                    value: value
                )

                if fanOut.isEmpty {
                    log("AppEnvironment group command skipped uniqueId=\(uniqueId) key=\(key) no-members")
                    return
                }

                for command in fanOut {
                    let transactionId = await commandTransactionIdGenerator.next()
                    let commandValue = deviceCommandValue(from: command.value)
                    let request = TydomCommand.putDevicesData(
                        deviceId: String(command.deviceId),
                        endpointId: String(command.endpointId),
                        name: command.key,
                        value: commandValue,
                        transactionId: transactionId
                    )
                    let isShutterLikeCommand = key == "position" || key == "level"
                    if isShutterLikeCommand {
//                        let memberUniqueId = "\(command.endpointId)_\(command.deviceId)"
//                        log(
//                            "ShutterTrace command group-send source=\(uniqueId) member=\(memberUniqueId) tx=\(transactionId) key=\(command.key) value=\(command.value.traceString)"
//                        )
                    }

                    do {
                        try await client.send(text: request.request)
                        if isShutterLikeCommand {
                            log(
                                "ShutterTrace command group-send-success source=\(uniqueId) member=\(command.endpointId)_\(command.deviceId) tx=\(transactionId)"
                            )
                        }
                    } catch {
                        log(
                            "AppEnvironment group command failed uniqueId=\(uniqueId) member=\(command.endpointId)_\(command.deviceId) key=\(command.key) error=\(error)"
                        )
                    }
                }
                return
            }

            guard let device = await repository.device(uniqueId: uniqueId) else { return }

            let commandValue = deviceCommandValue(from: value)
            let transactionId = await commandTransactionIdGenerator.next()
            let command = TydomCommand.putDevicesData(
                deviceId: String(device.deviceId),
                endpointId: String(device.endpointId),
                name: key,
                value: commandValue,
                transactionId: transactionId
            )
            let isShutterCommand = device.group == .shutter || key == "position" || key == "level"
            if isShutterCommand {
//                log(
//                    "ShutterTrace command send uniqueId=\(uniqueId) deviceId=\(device.deviceId) endpointId=\(device.endpointId) tx=\(transactionId) key=\(key) value=\(value.traceString) usage=\(device.usage)"
//                )
            }

            do {
                try await client.send(text: command.request)
                if isShutterCommand {
                    log("ShutterTrace command send-success uniqueId=\(uniqueId) tx=\(transactionId)")
                }
            } catch {
                log("AppEnvironment command failed uniqueId=\(uniqueId) key=\(key) error=\(error)")
            }
        }

        return AppEnvironment(
            repository: repository,
            groupRepository: groupRepository,
            newShutterRepository: newShutterRepository,
            sendDeviceCommand: sendDeviceCommand,
            log: log
        )
    }
}

private actor CommandTransactionIdGenerator {
    private let now: @Sendable () -> Date
    private var lastIssued: UInt64 = 0

    init(now: @escaping @Sendable () -> Date) {
        self.now = now
    }

    func next() -> String {
        let milliseconds = UInt64(now().timeIntervalSince1970 * 1000)
        let candidate = milliseconds * 1_000
        if candidate <= lastIssued {
            lastIssued += 1
        } else {
            lastIssued = candidate
        }
        return String(lastIssued)
    }
}

private func deviceCommandValue(from value: PayloadValue) -> TydomCommand.DeviceDataValue {
    switch value {
    case .bool(let flag):
        return .bool(flag)
    case .number(let number):
        return .int(Int(number.rounded()))
    case .string(let text):
        return .string(text)
    case .null, .object, .array:
        return .null
    }
}

enum AppDirectories {
    static func databaseURL() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = baseURL.appendingPathComponent("MoDyt", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("tydom.sqlite")
    }
}
