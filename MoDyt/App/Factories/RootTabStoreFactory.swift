import SwiftUI
import DeltaDoreClient

struct RootTabStoreFactory {
    let make: @MainActor () -> RootTabStore

    static func live(environment: AppEnvironment) -> RootTabStoreFactory {
        let gatewayBootstrapper = RootTabGatewayBootstrapper.live(environment: environment)
        let reconnectionRecovery = RootTabForegroundRecovery.live(environment: environment)
        return RootTabStoreFactory {
            RootTabStore(
                dependencies: .init(
                    bootstrapGateway: gatewayBootstrapper.run,
                    setAppActive: environment.client.setCurrentConnectionAppActive,
                    runForegroundRecovery: reconnectionRecovery.run,
                    requestDisconnect: environment.requestDisconnect
                )
            )
        }
    }
}

private struct RootTabForegroundRecovery: Sendable {
    let run: @Sendable () async -> RootTabForegroundRecoveryResult

    static func live(environment: AppEnvironment) -> RootTabForegroundRecovery {
        let pipeline = Pipeline(
            isConnectionAlive: {
                await environment.client.isCurrentConnectionAlive(timeout: 2.0)
            },
            renewConnection: {
                do {
                    _ = try await environment.client.connectWithStoredCredentials(
                        options: .init(mode: .auto)
                    )
                    return true
                } catch {
                    environment.log("RootTab reconnect failed error=\(error)")
                    return false
                }
            }
        )
        return RootTabForegroundRecovery(run: pipeline.run)
    }

    private struct Pipeline: Sendable {
        let isConnectionAlive: @Sendable () async -> Bool
        let renewConnection: @Sendable () async -> Bool

        func run() async -> RootTabForegroundRecoveryResult {
            if await isConnectionAlive() {
                return .alive
            }

            let didReconnect = await renewConnection()
            return didReconnect ? .reconnected : .failed
        }
    }
}

private struct RootTabGatewayBootstrapper: Sendable {
    let run: @Sendable () async -> RootTabBootstrapResult

    static func live(environment: AppEnvironment) -> RootTabGatewayBootstrapper {
        let preparePersistence: @Sendable () async -> Void = {
            try? await environment.repository.startIfNeeded()
            try? await environment.sceneRepository.startIfNeeded()
            try? await environment.groupRepository.startIfNeeded()
            try? await environment.newShutterRepository.startIfNeeded()
        }
        let decodeMessages: @Sendable () async -> AsyncStream<TydomMessage> = {
            await environment.client.decodedMessages(logger: environment.log)
        }
        let applyMessage: @Sendable (TydomMessage) async -> Void = { message in
            await environment.repository.applyMessage(message)
            await environment.sceneRepository.applyMessage(message)
            await environment.groupRepository.applyMessage(message)
        }
        let sendText: @Sendable (String) async throws -> Void = { text in
            try await environment.client.send(text: text)
        }
        let pipeline = Pipeline(
            log: environment.log,
            preparePersistence: preparePersistence,
            decodeMessages: decodeMessages,
            applyMessage: applyMessage,
            sendText: sendText,
            shouldRequestAreasData: {
                await environment.repository.hasLinkedAreaDevices()
            }
        )
        let runtime = Runtime(pipeline: pipeline)

        return RootTabGatewayBootstrapper(run: runtime.runBootstrap)
    }

    private actor Runtime {
        private let pipeline: Pipeline
        private let acknowledgements = RootTabBootstrapAcknowledgementTracker()
        private var streamTask: Task<Void, Never>?

        init(pipeline: Pipeline) {
            self.pipeline = pipeline
        }

        func runBootstrap() async -> RootTabBootstrapResult {
            restartMessageStream()
            return await pipeline.runBootstrap(acknowledgements: acknowledgements)
        }

        private func restartMessageStream() {
            streamTask?.cancel()
            streamTask = Task { [pipeline, acknowledgements] in
                await pipeline.streamMessages(acknowledgements: acknowledgements)
            }
        }
    }

    private struct Pipeline: Sendable {
        enum BootstrapRequestResult: Sendable {
            case success
            case failed(String)
        }

        let log: @Sendable (String) -> Void
        let preparePersistence: @Sendable () async -> Void
        let decodeMessages: @Sendable () async -> AsyncStream<TydomMessage>
        let applyMessage: @Sendable (TydomMessage) async -> Void
        let sendText: @Sendable (String) async throws -> Void
        let shouldRequestAreasData: @Sendable () async -> Bool
        let acknowledgementTimeout: Duration = .seconds(5)

        func streamMessages(
            acknowledgements: RootTabBootstrapAcknowledgementTracker
        ) async {
            await preparePersistence()
            log("Message stream started")
            let messages = await decodeMessages()
            for await message in messages {
                guard !Task.isCancelled else { return }
                log("Message received \(message.logDescription)")
                logShutterIngress(message)
                await applyMessage(message)
                await acknowledgements.track(message)
            }
            log("Message stream finished")
        }

        private func logShutterIngress(_ message: TydomMessage) {
            guard case .devices(let devices, let transactionId) = message else { return }

            let shutterUpdates = devices.compactMap { device -> String? in
                guard DeviceGroup.from(usage: device.usage) == .shutter else { return nil }
                let position = device.data["position"]?.traceString
                    ?? device.data["level"]?.traceString
                    ?? "nil"
                return "\(device.uniqueId):\(position)"
            }

            guard shutterUpdates.isEmpty == false else { return }
            log(
                "ShutterTrace ingress tx=\(transactionId ?? "nil") updates=\(shutterUpdates.joined(separator: ","))"
            )
        }

        func runBootstrap(
            acknowledgements: RootTabBootstrapAcknowledgementTracker
        ) async -> RootTabBootstrapResult {
            await preparePersistence()

            let transactionSeed = bootstrapTransactionSeed()
            var offset: UInt64 = 0

            let preAreaSequence: [(label: String, uriOrigin: String, command: @Sendable (String) -> TydomCommand)] = [
                ("configs-file", "/configs/file", TydomCommand.configsFile),
                ("devices-meta", "/devices/meta", TydomCommand.devicesMeta),
                ("devices-cmeta", "/devices/cmeta", TydomCommand.devicesCmeta),
                ("devices-data", "/devices/data", TydomCommand.devicesData)
            ]
            let postAreaSequence: [(label: String, uriOrigin: String, command: @Sendable (String) -> TydomCommand)] = [
                ("scenarios-file", "/scenarios/file", TydomCommand.scenariosFile),
                ("groups-file", "/groups/file", TydomCommand.groupsFile)
            ]

            for request in preAreaSequence {
                let result = await sendBootstrapRequest(
                    request.label,
                    expectedUriOrigin: request.uriOrigin,
                    makeCommand: request.command,
                    transactionSeed: transactionSeed,
                    offset: offset,
                    acknowledgements: acknowledgements
                )
                offset += 1

                guard !Task.isCancelled else {
                    return .failed("Bootstrap cancelled")
                }

                if case .failed(let message) = result {
                    return .failed(message)
                }
            }

            if await shouldRequestAreasData() {
                let areasResult = await sendBootstrapRequest(
                    "areas-data",
                    expectedUriOrigin: "/areas/data",
                    makeCommand: TydomCommand.areasData,
                    transactionSeed: transactionSeed,
                    offset: offset,
                    acknowledgements: acknowledgements
                )
                offset += 1

                guard !Task.isCancelled else {
                    return .failed("Bootstrap cancelled")
                }

                if case .failed(let message) = areasResult {
                    return .failed(message)
                }
            } else {
                log("Skip areas-data (no linked area devices)")
            }

            for request in postAreaSequence {
                let result = await sendBootstrapRequest(
                    request.label,
                    expectedUriOrigin: request.uriOrigin,
                    makeCommand: request.command,
                    transactionSeed: transactionSeed,
                    offset: offset,
                    acknowledgements: acknowledgements
                )
                offset += 1

                guard !Task.isCancelled else {
                    return .failed("Bootstrap cancelled")
                }

                if case .failed(let message) = result {
                    return .failed(message)
                }
            }
            return .completed
        }

        private func sendBootstrapRequest(
            _ label: String,
            expectedUriOrigin: String,
            makeCommand: @Sendable (String) -> TydomCommand,
            transactionSeed: UInt64,
            offset: UInt64,
            requiresAcknowledgement: Bool = true,
            acknowledgements: RootTabBootstrapAcknowledgementTracker
        ) async -> BootstrapRequestResult {
            let transactionId = bootstrapTransactionId(seed: transactionSeed, offset: offset)
            let command = makeCommand(transactionId)
            return await sendBootstrapRequest(
                label,
                command: command,
                transactionId: transactionId,
                expectedUriOrigin: expectedUriOrigin,
                requiresAcknowledgement: requiresAcknowledgement,
                acknowledgements: acknowledgements
            )
        }

        private func sendBootstrapRequest(
            _ label: String,
            command: TydomCommand,
            transactionId: String,
            expectedUriOrigin: String? = nil,
            requiresAcknowledgement: Bool,
            acknowledgements: RootTabBootstrapAcknowledgementTracker
        ) async -> BootstrapRequestResult {
            guard !Task.isCancelled else {
                return .failed("Bootstrap cancelled")
            }

            do {
                log("Send \(label) tx=\(transactionId)")
                try await sendText(command.request)
            } catch {
                guard !Task.isCancelled else {
                    return .failed("Bootstrap cancelled")
                }
                let message = "Failed to send \(label): \(error.localizedDescription)"
                log(message)
                return .failed(message)
            }

            guard requiresAcknowledgement else {
                return .success
            }

            let response = await acknowledgements.awaitResponse(
                for: transactionId,
                expectedUriOrigin: expectedUriOrigin,
                timeout: acknowledgementTimeout
            )
            guard !Task.isCancelled else {
                return .failed("Bootstrap cancelled")
            }

            switch response {
            case .acknowledged(let statusCode):
                log("Ack \(label) status=\(statusCode) tx=\(transactionId)")
                return .success
            case .rejected(let statusCode):
                let message = "Gateway rejected \(label) (status \(statusCode))"
                log(message)
                return .failed(message)
            case .timedOut:
                let message = "Timed out waiting for \(label) acknowledgement"
                log(message)
                return .failed(message)
            }
        }

        private func bootstrapTransactionSeed() -> UInt64 {
            UInt64(Date().timeIntervalSince1970 * 1000) * 100
        }

        private func bootstrapTransactionId(seed: UInt64, offset: UInt64) -> String {
            String(seed + offset)
        }
    }
}

private actor RootTabBootstrapAcknowledgementTracker {
    enum Response: Sendable, Equatable {
        case acknowledged(statusCode: Int)
        case rejected(statusCode: Int)
        case timedOut
    }

    private struct PendingReply {
        let expectedUriOrigin: String?
        let continuation: CheckedContinuation<Response, Never>
        let timeoutTask: Task<Void, Never>
    }

    private struct BufferedReply: Sendable {
        let transactionId: String
        let uriOrigin: String
        let status: Response
    }

    private var pendingReplies: [String: PendingReply] = [:]
    private var bufferedReplies: [BufferedReply] = []
    private var bufferedDefaultReplies: [Response] = []
    private let maxBufferedReplies = 64
    private static let gatewayDefaultTransactionId = "0"

    func track(_ message: TydomMessage) {
        switch message {
        case .raw(let raw):
            guard case .response(let response)? = raw.frame else { return }
            guard let transactionId = raw.transactionId, transactionId.isEmpty == false else { return }
            resolve(
                transactionId: transactionId,
                uriOrigin: raw.uriOrigin,
                status: status(from: response.status)
            )

        case .gatewayInfo(_, let transactionId),
             .devices(_, let transactionId),
             .scenarios(_, let transactionId),
             .groupMetadata(_, let transactionId),
             .groups(_, let transactionId),
             .moments(_, let transactionId),
             .areas(_, let transactionId):
            guard let transactionId, transactionId.isEmpty == false else { return }
            resolve(
                transactionId: transactionId,
                uriOrigin: nil,
                status: .acknowledged(statusCode: 200)
            )

        case .echo:
            return
        }
    }

    func awaitResponse(
        for transactionId: String,
        expectedUriOrigin: String? = nil,
        timeout: Duration
    ) async -> Response {
        if let buffered = takeBufferedReply(
            transactionId: transactionId,
            expectedUriOrigin: expectedUriOrigin
        ) {
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
                    expectedUriOrigin: expectedUriOrigin,
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

    private func resolveIfPending(transactionId: String, status: Response) {
        guard pendingReplies[transactionId] != nil else { return }
        resolve(transactionId: transactionId, uriOrigin: nil, status: status)
    }

    private func resolve(
        transactionId: String,
        uriOrigin: String?,
        status: Response
    ) {
        if let pending = pendingReplies.removeValue(forKey: transactionId) {
            pending.timeoutTask.cancel()
            pending.continuation.resume(returning: status)
            return
        }

        // Some gateways answer bootstrap GET commands with Transac-Id: 0.
        // If we have a pending bootstrap request for this URI, treat this as its ACK.
        if transactionId == Self.gatewayDefaultTransactionId,
           let uriOrigin,
           let (expectedTransactionId, pending) = pendingReplies.first(where: { (_, reply) in
               reply.expectedUriOrigin == uriOrigin
           }) {
            pendingReplies.removeValue(forKey: expectedTransactionId)
            pending.timeoutTask.cancel()
            pending.continuation.resume(returning: status)
            return
        }

        if transactionId == Self.gatewayDefaultTransactionId,
           pendingReplies.count == 1,
           let (expectedTransactionId, pending) = pendingReplies.first {
            pendingReplies.removeValue(forKey: expectedTransactionId)
            pending.timeoutTask.cancel()
            pending.continuation.resume(returning: status)
            return
        }

        if transactionId == Self.gatewayDefaultTransactionId, uriOrigin == nil {
            bufferDefaultReply(status)
            return
        }

        guard let uriOrigin else { return }
        bufferReply(
            BufferedReply(
                transactionId: transactionId,
                uriOrigin: uriOrigin,
                status: status
            )
        )
    }

    private func takeBufferedReply(
        transactionId: String,
        expectedUriOrigin: String?
    ) -> Response? {
        if let index = bufferedReplies.firstIndex(where: { $0.transactionId == transactionId }) {
            return bufferedReplies.remove(at: index).status
        }

        // Some bootstrap replies come back with Transac-Id: 0.
        if let expectedUriOrigin,
           let index = bufferedReplies.firstIndex(where: { reply in
               reply.transactionId == Self.gatewayDefaultTransactionId
                   && reply.uriOrigin == expectedUriOrigin
           }) {
            return bufferedReplies.remove(at: index).status
        }

        if expectedUriOrigin != nil, bufferedDefaultReplies.isEmpty == false {
            return bufferedDefaultReplies.removeFirst()
        }

        return nil
    }

    private func bufferReply(_ reply: BufferedReply) {
        if let existingIndex = bufferedReplies.firstIndex(where: { existing in
            existing.transactionId == reply.transactionId && existing.uriOrigin == reply.uriOrigin
        }) {
            bufferedReplies.remove(at: existingIndex)
        }
        bufferedReplies.append(reply)
        trimBufferedRepliesIfNeeded()
    }

    private func bufferDefaultReply(_ reply: Response) {
        bufferedDefaultReplies.append(reply)
        trimBufferedRepliesIfNeeded()
    }

    private func trimBufferedRepliesIfNeeded() {
        while bufferedReplies.count > maxBufferedReplies {
            bufferedReplies.removeFirst()
        }
        while bufferedDefaultReplies.count > maxBufferedReplies {
            bufferedDefaultReplies.removeFirst()
        }
    }

    private func status(from statusCode: Int) -> Response {
        if (200..<300).contains(statusCode) {
            return .acknowledged(statusCode: statusCode)
        }
        return .rejected(statusCode: statusCode)
    }
}

private extension TydomMessage {
    var logDescription: String {
        switch self {
        case .devices(let devices, let transactionId):
            return "devices count=\(devices.count) tx=\(transactionId ?? "nil")"
        case .gatewayInfo(_, let transactionId):
            return "gatewayInfo tx=\(transactionId ?? "nil")"
        case .scenarios(let scenarios, let transactionId):
            return "scenarios count=\(scenarios.count) tx=\(transactionId ?? "nil")"
        case .groupMetadata(let groups, let transactionId):
            return "groupMetadata count=\(groups.count) tx=\(transactionId ?? "nil")"
        case .groups(let groups, let transactionId):
            return "groups count=\(groups.count) tx=\(transactionId ?? "nil")"
        case .moments(_, let transactionId):
            return "moments tx=\(transactionId ?? "nil")"
        case .areas(let areas, let transactionId):
            return "areas count=\(areas.count) tx=\(transactionId ?? "nil")"
        case .echo(let echo):
            return "echo status=\(echo.statusCode) tx=\(echo.transactionId) uri=\(echo.uriOrigin)"
        case .raw(let raw):
            let origin = raw.uriOrigin ?? "nil"
            let tx = raw.transactionId ?? "nil"
            let bodyCount = raw.frame?.body?.count ?? 0
            let preview = raw.frame?.body
                .flatMap { data in
                    String(data: data.prefix(200), encoding: .isoLatin1)
                        ?? String(decoding: data.prefix(200), as: UTF8.self)
                } ?? ""
            let suffix = preview.isEmpty ? "" : " bodyPreview=\(preview)"
            return "raw bytes=\(raw.payload.count) uri=\(origin) tx=\(tx) body=\(bodyCount)\(suffix)"
        }
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
        case .object(let value):
            return "object(keys:\(value.keys.sorted()))"
        case .array(let value):
            return "array(count:\(value.count))"
        case .null:
            return "null"
        }
    }
}

private struct RootTabStoreFactoryKey: EnvironmentKey {
    static var defaultValue: RootTabStoreFactory {
        RootTabStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var rootTabStoreFactory: RootTabStoreFactory {
        get { self[RootTabStoreFactoryKey.self] }
        set { self[RootTabStoreFactoryKey.self] = newValue }
    }
}
