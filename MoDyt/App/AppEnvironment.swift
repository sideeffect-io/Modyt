import Foundation
import DeltaDoreClient

enum SceneExecutionResult: Sendable, Equatable {
    case acknowledged(statusCode: Int)
    case rejected(statusCode: Int)
    case sentWithoutAcknowledgement
    case invalidSceneIdentifier
    case sendFailed
}

struct AppEnvironment: Sendable {
    let client: DeltaDoreClient
    let repository: DeviceRepository
    let sceneRepository: SceneRepository
    let groupRepository: GroupRepository
    let dashboardRepository: DashboardRepository
    let newShutterRepository: ShutterRepository
    let requestRefreshAll: @Sendable () async -> Void
    let sendDeviceCommand: @Sendable (String, String, JSONValue) async -> Void
    let executeScene: @Sendable (String) async -> SceneExecutionResult
    let requestDisconnect: @Sendable () async -> Void
    let now: @Sendable () -> Date
    let log: @Sendable (String) -> Void

    static func live() -> AppEnvironment {
        let databaseURL = AppDirectories.databaseURL()
        let client = DeltaDoreClient.live()
        let now: @Sendable () -> Date = Date.init
        let log: @Sendable (String) -> Void = { message in
            #if DEBUG
            print("[MoDyt] \(message)")
            #endif
        }
        let sceneExecutionStatusStore = SceneExecutionStatusStore()
        let repository = DeviceRepository(databasePath: databaseURL.path, log: log)
        let sceneRepository = SceneRepository(
            databasePath: databaseURL.path,
            log: log,
            trackMessage: { message in
                await sceneExecutionStatusStore.track(message)
            }
        )
        let groupRepository = GroupRepository(
            databasePath: databaseURL.path,
            deviceRepository: repository,
            log: log
        )
        let dashboardRepository = DashboardRepository(
            deviceRepository: repository,
            sceneRepository: sceneRepository,
            groupRepository: groupRepository
        )
        let newShutterRepository = ShutterRepository(
            databasePath: databaseURL.path,
            deviceRepository: repository,
            log: log
        )
        let commandTransactionIdGenerator = CommandTransactionIdGenerator(now: now)

        let requestRefreshAll: @Sendable () async -> Void = {
            do {
                try await client.send(text: TydomCommand.refreshAll().request)
            } catch {
                log("AppEnvironment refresh failed error=\(error)")
            }
        }

        let sendDeviceCommand: @Sendable (String, String, JSONValue) async -> Void = { uniqueId, key, value in
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
                        let memberUniqueId = "\(command.endpointId)_\(command.deviceId)"
                        log(
                            "ShutterTrace command group-send source=\(uniqueId) member=\(memberUniqueId) tx=\(transactionId) key=\(command.key) value=\(command.value.traceString)"
                        )
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
                log(
                    "ShutterTrace command send uniqueId=\(uniqueId) deviceId=\(device.deviceId) endpointId=\(device.endpointId) tx=\(transactionId) key=\(key) value=\(value.traceString) usage=\(device.usage)"
                )
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

        let executeScene: @Sendable (String) async -> SceneExecutionResult = { uniqueId in
            guard let sceneId = SceneRecord.sceneId(from: uniqueId) else {
                return .invalidSceneIdentifier
            }

            let transactionId = TydomCommand.defaultTransactionId(now: now)
            let command = TydomCommand.activateScenario(
                String(sceneId),
                transactionId: transactionId
            )

            do {
                try await client.send(text: command.request)
            } catch {
                log("AppEnvironment scene execution send failed uniqueId=\(uniqueId) tx=\(transactionId) error=\(error)")
                return .sendFailed
            }

            let status = await sceneExecutionStatusStore.awaitScenarioExecutionStatus(
                for: transactionId,
                timeout: .seconds(3)
            )

            switch status {
            case .success(let statusCode):
                return .acknowledged(statusCode: statusCode)
            case .failure(let statusCode):
                return .rejected(statusCode: statusCode)
            case .timedOut:
                return .sentWithoutAcknowledgement
            }
        }

        let requestDisconnect: @Sendable () async -> Void = {
            await client.disconnectCurrentConnection()
            await client.clearStoredData()
        }

        return AppEnvironment(
            client: client,
            repository: repository,
            sceneRepository: sceneRepository,
            groupRepository: groupRepository,
            dashboardRepository: dashboardRepository,
            newShutterRepository: newShutterRepository,
            requestRefreshAll: requestRefreshAll,
            sendDeviceCommand: sendDeviceCommand,
            executeScene: executeScene,
            requestDisconnect: requestDisconnect,
            now: now,
            log: log
        )
    }
}

private enum SceneExecutionGatewayStatus: Sendable, Equatable {
    case success(Int)
    case failure(Int)
    case timedOut
}

private actor SceneExecutionStatusStore {
    private struct PendingReply {
        let continuation: CheckedContinuation<SceneExecutionGatewayStatus, Never>
        let timeoutTask: Task<Void, Never>
    }

    private var pendingReplies: [String: PendingReply] = [:]
    private var bufferedReplies: [String: SceneExecutionGatewayStatus] = [:]
    private var bufferedOrder: [String] = []
    private let maxBufferedReplies = 32

    func track(_ message: TydomMessage) {
        guard case .echo(let echo) = message else { return }
        guard echo.uriOrigin.hasPrefix("/scenarios/"), echo.uriOrigin != "/scenarios/file" else { return }

        let status: SceneExecutionGatewayStatus = if (200..<300).contains(echo.statusCode) {
            .success(echo.statusCode)
        } else {
            .failure(echo.statusCode)
        }

        resolve(transactionId: echo.transactionId, status: status)
    }

    func awaitScenarioExecutionStatus(
        for transactionId: String,
        timeout: Duration
    ) async -> SceneExecutionGatewayStatus {
        if let buffered = bufferedReplies.removeValue(forKey: transactionId) {
            bufferedOrder.removeAll { $0 == transactionId }
            return buffered
        }

        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                let timeoutTask = Task { [transactionId, timeout] in
                    do {
                        try await Task.sleep(for: timeout)
                    } catch {
                        return
                    }
                    self.resolveIfPending(transactionId: transactionId, status: .timedOut)
                }
                pendingReplies[transactionId] = PendingReply(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            Task { [transactionId] in
                await self.resolveIfPending(transactionId: transactionId, status: .timedOut)
            }
        }
    }

    private func resolveIfPending(transactionId: String, status: SceneExecutionGatewayStatus) {
        guard pendingReplies[transactionId] != nil else { return }
        resolve(transactionId: transactionId, status: status)
    }

    private func resolve(transactionId: String, status: SceneExecutionGatewayStatus) {
        if let pending = pendingReplies.removeValue(forKey: transactionId) {
            pending.timeoutTask.cancel()
            pending.continuation.resume(returning: status)
            return
        }

        bufferedReplies[transactionId] = status
        bufferedOrder.removeAll { $0 == transactionId }
        bufferedOrder.append(transactionId)
        trimBufferedRepliesIfNeeded()
    }

    private func trimBufferedRepliesIfNeeded() {
        while bufferedOrder.count > maxBufferedReplies {
            let oldest = bufferedOrder.removeFirst()
            bufferedReplies.removeValue(forKey: oldest)
        }
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

private func deviceCommandValue(from value: JSONValue) -> TydomCommand.DeviceDataValue {
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

private extension JSONValue {
    var traceString: String {
        switch self {
        case .string(let text):
            return "\"\(text)\""
        case .number(let number):
            if number.rounded(.towardZero) == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        case .object(let value):
            return "object(keys:\(value.keys.sorted()))"
        case .array(let value):
            return "array(count:\(value.count))"
        }
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
