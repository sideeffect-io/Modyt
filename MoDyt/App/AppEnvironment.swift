import Foundation
import DeltaDoreClient

struct AppEnvironment: Sendable {
    let client: DeltaDoreClient
    let repository: DeviceRepository
    let sceneRepository: SceneRepository
    let dashboardRepository: DashboardRepository
    let shutterRepository: ShutterRepository
    let setOnDidDisconnect: @Sendable (@escaping @MainActor () -> Void) async -> Void
    let requestRefreshAll: @Sendable () async -> Void
    let sendDeviceCommand: @Sendable (String, String, JSONValue) async -> Void
    let requestDisconnect: @Sendable () async -> Void
    let now: @Sendable () -> Date
    let log: @Sendable (String) -> Void

    static func live() -> AppEnvironment {
        let databaseURL = AppDirectories.databaseURL()
        let client = DeltaDoreClient.live()
        let log: @Sendable (String) -> Void = { message in
            #if DEBUG
            print("[MoDyt] \(message)")
            #endif
        }
        let repository = DeviceRepository(databasePath: databaseURL.path, log: log)
        let sceneRepository = SceneRepository(databasePath: databaseURL.path, log: log)
        let dashboardRepository = DashboardRepository(
            deviceRepository: repository,
            sceneRepository: sceneRepository
        )
        let shutterRepository = ShutterRepository(
            databasePath: databaseURL.path,
            deviceRepository: repository,
            log: log
        )
        let disconnectHandlerStore = RuntimeDisconnectHandlerStore()

        let setOnDidDisconnect: @Sendable (@escaping @MainActor () -> Void) async -> Void = { callback in
            await disconnectHandlerStore.set(callback)
        }

        let requestRefreshAll: @Sendable () async -> Void = {
            do {
                try await client.send(text: TydomCommand.refreshAll().request)
            } catch {
                log("AppEnvironment refresh failed error=\(error)")
            }
        }

        let sendDeviceCommand: @Sendable (String, String, JSONValue) async -> Void = { uniqueId, key, value in
            guard let device = await repository.device(uniqueId: uniqueId) else { return }

            let commandValue = deviceCommandValue(from: value)
            let command = TydomCommand.putDevicesData(
                deviceId: String(device.deviceId),
                endpointId: String(device.endpointId),
                name: key,
                value: commandValue
            )

            do {
                try await client.send(text: command.request)
            } catch {
                log("AppEnvironment command failed uniqueId=\(uniqueId) key=\(key) error=\(error)")
            }
        }

        let requestDisconnect: @Sendable () async -> Void = {
            let onDidDisconnect = await disconnectHandlerStore.take()
            await client.disconnectCurrentConnection()
            await shutterRepository.clearAll()
            await client.clearStoredData()
            if let onDidDisconnect {
                await onDidDisconnect()
            }
        }

        return AppEnvironment(
            client: client,
            repository: repository,
            sceneRepository: sceneRepository,
            dashboardRepository: dashboardRepository,
            shutterRepository: shutterRepository,
            setOnDidDisconnect: setOnDidDisconnect,
            requestRefreshAll: requestRefreshAll,
            sendDeviceCommand: sendDeviceCommand,
            requestDisconnect: requestDisconnect,
            now: Date.init,
            log: log
        )
    }
}

private actor RuntimeDisconnectHandlerStore {
    private var onDidDisconnect: (@MainActor () -> Void)?

    func set(_ callback: @escaping @MainActor () -> Void) {
        onDidDisconnect = callback
    }

    func take() -> (@MainActor () -> Void)? {
        let callback = onDidDisconnect
        onDidDisconnect = nil
        return callback
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
