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
    let dashboardRepository: DashboardRepository
    let shutterRepository: ShutterRepository
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
        let dashboardRepository = DashboardRepository(
            deviceRepository: repository,
            sceneRepository: sceneRepository
        )
        let shutterRepository = ShutterRepository(
            databasePath: databaseURL.path,
            deviceRepository: repository,
            log: log
        )

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
            await shutterRepository.clearAll()
            await client.clearStoredData()
        }

        return AppEnvironment(
            client: client,
            repository: repository,
            sceneRepository: sceneRepository,
            dashboardRepository: dashboardRepository,
            shutterRepository: shutterRepository,
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
        guard case .raw(let raw) = message else { return }
        guard let transactionId = raw.transactionId else { return }
        guard let uriOrigin = raw.uriOrigin else { return }
        guard uriOrigin.hasPrefix("/scenarios/"), uriOrigin != "/scenarios/file" else { return }
        guard let frame = raw.frame, case .response(let response) = frame else { return }

        let status: SceneExecutionGatewayStatus = if (200..<300).contains(response.status) {
            .success(response.status)
        } else {
            .failure(response.status)
        }

        resolve(transactionId: transactionId, status: status)
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
