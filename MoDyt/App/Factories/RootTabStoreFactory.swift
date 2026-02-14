import SwiftUI
import DeltaDoreClient

struct RootTabStoreFactory {
    let make: @MainActor () -> RootTabStore

    static func live(environment: AppEnvironment) -> RootTabStoreFactory {
        RootTabStoreFactory {
            return RootTabStore(
                dependencies: .init(
                    bootstrapGateway: RootTabGatewayBootstrapper.live(environment: environment).run,
                    setAppActive: { isActive in await environment.client.setCurrentConnectionAppActive(isActive) },
                    runForegroundRecovery: RootTabForegroundRecovery.live(environment: environment).run,
                    requestDisconnect: environment.requestDisconnect
                )
            )
        }
    }
}

private struct RootTabForegroundRecovery: Sendable {
    let run: @Sendable (@escaping @MainActor (RootTabForegroundRecoveryPhase) -> Void) async -> Void

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

        func run(
            report: @escaping @MainActor (RootTabForegroundRecoveryPhase) -> Void
        ) async {
            if await isConnectionAlive() {
                await report(.alive)
                return
            }

            await report(.reconnecting)
            let didReconnect = await renewConnection()
            await report(didReconnect ? .reconnected : .failed)
        }
    }
}

private struct RootTabGatewayBootstrapper: Sendable {
    let run: @Sendable () async -> Void

    static func live(environment: AppEnvironment) -> RootTabGatewayBootstrapper {
        let preparePersistence: @Sendable () async -> Void = {
            try? await environment.repository.startIfNeeded()
            try? await environment.sceneRepository.startIfNeeded()
            try? await environment.shutterRepository.startIfNeeded()
        }
        let decodeMessages: @Sendable () async -> AsyncStream<TydomMessage> = {
            await environment.client.decodedMessages(logger: environment.log)
        }
        let applyMessage: @Sendable (TydomMessage) async -> Void = { message in
            await environment.repository.applyMessage(message)
            await environment.sceneRepository.applyMessage(message)
        }
        let sendText: @Sendable (String) async -> Void = { text in
            try? await environment.client.send(text: text)
        }
        let pipeline = Pipeline(
            log: environment.log,
            preparePersistence: preparePersistence,
            decodeMessages: decodeMessages,
            applyMessage: applyMessage,
            sendText: sendText
        )

        return RootTabGatewayBootstrapper(run: pipeline.run)
    }

    private struct Pipeline: Sendable {
        let log: @Sendable (String) -> Void
        let preparePersistence: @Sendable () async -> Void
        let decodeMessages: @Sendable () async -> AsyncStream<TydomMessage>
        let applyMessage: @Sendable (TydomMessage) async -> Void
        let sendText: @Sendable (String) async -> Void

        func run() async {
            await preparePersistence()

            await withTaskGroup(of: Void.self) { group in
                group.addTask {
                    await streamMessages()
                }
                group.addTask {
                    await sendBootstrapRequests()
                }

                while await group.next() != nil {
                    guard !Task.isCancelled else {
                        group.cancelAll()
                        return
                    }
                }
            }
        }

        private func streamMessages() async {
            log("Message stream started")
            let messages = await decodeMessages()
            for await message in messages {
                guard !Task.isCancelled else { return }
                log("Message received \(message.logDescription)")
                await applyMessage(message)
            }
            log("Message stream finished")
        }

        private func sendBootstrapRequests() async {
            log("Send configs-file")
            await sendText(TydomCommand.configsFile().request)
            log("Send devices-meta")
            await sendText(TydomCommand.devicesMeta().request)
            log("Send devices-cmeta")
            await sendText(TydomCommand.devicesCmeta().request)
            log("Send devices-data")
            await sendText(TydomCommand.devicesData().request)
            log("Send areas-data")
            await sendText(TydomCommand.areasData().request)
            log("Send scenarios-file")
            await sendText(TydomCommand.scenariosFile().request)
            log("Send refresh-all")
            await sendText(TydomCommand.refreshAll().request)
        }
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
        case .groups(_, let transactionId):
            return "groups tx=\(transactionId ?? "nil")"
        case .moments(_, let transactionId):
            return "moments tx=\(transactionId ?? "nil")"
        case .areas(let areas, let transactionId):
            return "areas count=\(areas.count) tx=\(transactionId ?? "nil")"
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
