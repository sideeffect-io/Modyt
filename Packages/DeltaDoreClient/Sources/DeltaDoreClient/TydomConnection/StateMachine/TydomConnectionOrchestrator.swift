import Foundation

public struct TydomConnectionOrchestrator: Sendable {
    public struct Dependencies: Sendable {
        public let loadCredentials: @Sendable () async -> TydomGatewayCredentials?
        public let saveCredentials: @Sendable (_ credentials: TydomGatewayCredentials) async -> Void
        public let discoverLocal: @Sendable () async -> [TydomLocalGateway]
        public let connectLocal: @Sendable (_ host: String) async -> TydomConnection?
        public let connectRemote: @Sendable () async -> TydomConnection?
        public let emitDecision: @Sendable (_ decision: TydomConnectionState.Decision) async -> Void

        public init(
            loadCredentials: @escaping @Sendable () async -> TydomGatewayCredentials?,
            saveCredentials: @escaping @Sendable (_ credentials: TydomGatewayCredentials) async -> Void,
            discoverLocal: @escaping @Sendable () async -> [TydomLocalGateway],
            connectLocal: @escaping @Sendable (_ host: String) async -> TydomConnection?,
            connectRemote: @escaping @Sendable () async -> TydomConnection?,
            emitDecision: @escaping @Sendable (_ decision: TydomConnectionState.Decision) async -> Void
        ) {
            self.loadCredentials = loadCredentials
            self.saveCredentials = saveCredentials
            self.discoverLocal = discoverLocal
            self.connectLocal = connectLocal
            self.connectRemote = connectRemote
            self.emitDecision = emitDecision
        }
    }

    private let dependencies: Dependencies

    public init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    public func run(initialState: TydomConnectionState = TydomConnectionState()) async {
        var state = initialState
        var actions: [TydomConnectionAction] = []
        (state, actions) = TydomConnectionStateMachine.reduce(state: state, event: .start)
        await execute(actions: actions, state: &state)
    }

    public func handle(event: TydomConnectionEvent, state: inout TydomConnectionState) async {
        let (next, actions) = TydomConnectionStateMachine.reduce(state: state, event: event)
        state = next
        await execute(actions: actions, state: &state)
    }

    private func execute(actions: [TydomConnectionAction], state: inout TydomConnectionState) async {
        for action in actions {
            switch action {
            case .loadCredentials:
                let credentials = await dependencies.loadCredentials()
                await handle(event: .credentialsLoaded(credentials), state: &state)
            case .saveCredentials(let credentials):
                await dependencies.saveCredentials(credentials)
                await handle(event: .credentialsSaved(credentials), state: &state)
            case .tryCachedIP(let host):
                let connection = await dependencies.connectLocal(host)
                if let connection {
                    await handle(event: .localConnectResult(success: true, host: host, connection: connection), state: &state)
                } else {
                    await handle(event: .cachedIPFailed, state: &state)
                }
            case .discoverLocal:
                let candidates = await dependencies.discoverLocal()
                await handle(event: .localDiscoveryFound(candidates), state: &state)
            case .connectLocal(let host):
                let connection = await dependencies.connectLocal(host)
                let success = connection != nil
                await handle(event: .localConnectResult(success: success, host: host, connection: connection), state: &state)
            case .connectRemote:
                let connection = await dependencies.connectRemote()
                let success = connection != nil
                await handle(event: .remoteConnectResult(success: success, connection: connection), state: &state)
            case .emitDecision(let decision):
                await dependencies.emitDecision(decision)
            }
        }
    }
}
