import Foundation

public struct TydomConnectionState: Sendable, Equatable {
    public enum Phase: Sendable, Equatable {
        case idle
        case loadingSiteList
        case selectingSite
        case loadingCredentials
        case tryingCachedIP
        case discoveringLocal
        case connectingLocal
        case connectingRemote
        case connected
        case failed
    }

    public enum ModeOverride: Sendable, Equatable {
        case none
        case forceLocal
        case forceRemote
    }

    public struct Decision: Sendable, Equatable {
        public enum Reason: String, Sendable, Equatable {
            case missingCredentials
            case overrideLocal
            case overrideRemote
            case cachedIPFailed
            case localDiscoveryFailed
            case localConnected
            case remoteConnected
            case localFailed
            case remoteFailed
        }

        public let mode: TydomConnection.Configuration.Mode
        public let reason: Reason
    }

    public let phase: Phase
    public let override: ModeOverride
    public let credentials: TydomGatewayCredentials?
    public let selectedGatewayMac: String?
    public let lastDecision: Decision?
    public let lastError: String?
    public let pendingLocalCandidates: [TydomLocalGateway]
    public let connectedConnection: TydomConnection?

    public init(
        phase: Phase = .idle,
        override: ModeOverride = .none,
        credentials: TydomGatewayCredentials? = nil,
        selectedGatewayMac: String? = nil,
        lastDecision: Decision? = nil,
        lastError: String? = nil,
        pendingLocalCandidates: [TydomLocalGateway] = [],
        connectedConnection: TydomConnection? = nil
    ) {
        self.phase = phase
        self.override = override
        self.credentials = credentials
        self.selectedGatewayMac = selectedGatewayMac
        self.lastDecision = lastDecision
        self.lastError = lastError
        self.pendingLocalCandidates = pendingLocalCandidates
        self.connectedConnection = connectedConnection
    }

    public static func == (lhs: TydomConnectionState, rhs: TydomConnectionState) -> Bool {
        lhs.phase == rhs.phase &&
        lhs.override == rhs.override &&
        lhs.credentials == rhs.credentials &&
        lhs.selectedGatewayMac == rhs.selectedGatewayMac &&
        lhs.lastDecision == rhs.lastDecision &&
        lhs.lastError == rhs.lastError &&
        lhs.pendingLocalCandidates == rhs.pendingLocalCandidates
    }
}

public enum TydomConnectionEvent: Sendable, Equatable {
    case start
    case overrideLocal
    case overrideRemote
    case clearOverride
    case credentialsLoaded(TydomGatewayCredentials?)
    case credentialsSaved(TydomGatewayCredentials)
    case cachedIPFailed
    case localDiscoveryFound([TydomLocalGateway])
    case localConnectResult(success: Bool, host: String?, connection: TydomConnection?)
    case remoteConnectResult(success: Bool, connection: TydomConnection?)
    case failure(String)

    public static func == (lhs: TydomConnectionEvent, rhs: TydomConnectionEvent) -> Bool {
        switch (lhs, rhs) {
        case (.start, .start),
             (.overrideLocal, .overrideLocal),
             (.overrideRemote, .overrideRemote),
             (.clearOverride, .clearOverride):
            return true
        case (.credentialsLoaded(let a), .credentialsLoaded(let b)):
            return a == b
        case (.credentialsSaved(let a), .credentialsSaved(let b)):
            return a == b
        case (.cachedIPFailed, .cachedIPFailed):
            return true
        case (.localDiscoveryFound(let a), .localDiscoveryFound(let b)):
            return a == b
        case (.localConnectResult(let successA, let hostA, _),
              .localConnectResult(let successB, let hostB, _)):
            return successA == successB && hostA == hostB
        case (.remoteConnectResult(let successA, _),
              .remoteConnectResult(let successB, _)):
            return successA == successB
        case (.failure(let a), .failure(let b)):
            return a == b
        default:
            return false
        }
    }
}

public enum TydomConnectionAction: Sendable, Equatable {
    case loadCredentials
    case saveCredentials(TydomGatewayCredentials)
    case tryCachedIP(String)
    case discoverLocal
    case connectLocal(String)
    case connectRemote
    case emitDecision(TydomConnectionState.Decision)
}

public struct TydomConnectionStateMachine {
    public static func reduce(
        state: TydomConnectionState,
        event: TydomConnectionEvent
    ) -> (TydomConnectionState, [TydomConnectionAction]) {
        switch event {
        case .start:
            return (
                TydomConnectionState(
                    phase: .loadingCredentials,
                    override: state.override,
                    credentials: state.credentials,
                    selectedGatewayMac: state.selectedGatewayMac,
                    lastDecision: state.lastDecision,
                    lastError: nil,
                    pendingLocalCandidates: [],
                    connectedConnection: state.connectedConnection
                ),
                [.loadCredentials]
            )

        case .overrideLocal:
            let next = TydomConnectionState(
                phase: state.phase,
                override: .forceLocal,
                credentials: state.credentials,
                selectedGatewayMac: state.selectedGatewayMac,
                lastDecision: state.lastDecision,
                lastError: nil,
                pendingLocalCandidates: state.pendingLocalCandidates,
                connectedConnection: state.connectedConnection
            )
            return (next, [])

        case .overrideRemote:
            let next = TydomConnectionState(
                phase: state.phase,
                override: .forceRemote,
                credentials: state.credentials,
                selectedGatewayMac: state.selectedGatewayMac,
                lastDecision: state.lastDecision,
                lastError: nil,
                pendingLocalCandidates: state.pendingLocalCandidates,
                connectedConnection: state.connectedConnection
            )
            return (next, [.connectRemote])

        case .clearOverride:
            let next = TydomConnectionState(
                phase: state.phase,
                override: .none,
                credentials: state.credentials,
                selectedGatewayMac: state.selectedGatewayMac,
                lastDecision: state.lastDecision,
                lastError: nil,
                pendingLocalCandidates: state.pendingLocalCandidates,
                connectedConnection: state.connectedConnection
            )
            return (next, [])

        case .credentialsLoaded(let credentials):
            guard let credentials else {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .missingCredentials
                )
                return (
                    TydomConnectionState(
                        phase: .failed,
                        override: state.override,
                        credentials: nil,
                        selectedGatewayMac: state.selectedGatewayMac,
                        lastDecision: decision,
                        lastError: "Missing gateway credentials",
                        connectedConnection: state.connectedConnection
                    ),
                    [.emitDecision(decision)]
                )
            }

            if state.override == .forceRemote {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .overrideRemote
                )
                return (
                    TydomConnectionState(
                        phase: .connectingRemote,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil,
                        connectedConnection: state.connectedConnection
                    ),
                    [.emitDecision(decision), .connectRemote]
                )
            }

            if state.override == .forceLocal {
                let decision = TydomConnectionState.Decision(
                    mode: .local(host: credentials.cachedLocalIP ?? ""),
                    reason: .overrideLocal
                )
                if let cached = credentials.cachedLocalIP, cached.isEmpty == false {
                    return (
                        TydomConnectionState(
                            phase: .tryingCachedIP,
                            override: state.override,
                            credentials: credentials,
                            selectedGatewayMac: credentials.mac,
                            lastDecision: decision,
                            lastError: nil,
                            connectedConnection: state.connectedConnection
                        ),
                        [.emitDecision(decision), .tryCachedIP(cached)]
                    )
                }
                return (
                    TydomConnectionState(
                        phase: .discoveringLocal,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil,
                        connectedConnection: state.connectedConnection
                    ),
                    [.emitDecision(decision), .discoverLocal]
                )
            }

            if let cached = credentials.cachedLocalIP, cached.isEmpty == false {
                let decision = TydomConnectionState.Decision(
                    mode: .local(host: cached),
                    reason: .localConnected
                )
                return (
                    TydomConnectionState(
                        phase: .tryingCachedIP,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil,
                        connectedConnection: state.connectedConnection
                    ),
                    [.emitDecision(decision), .tryCachedIP(cached)]
                )
            }

            return (
                TydomConnectionState(
                    phase: .discoveringLocal,
                    override: state.override,
                    credentials: credentials,
                    selectedGatewayMac: credentials.mac,
                    lastDecision: state.lastDecision,
                    lastError: nil,
                    connectedConnection: state.connectedConnection
                ),
                [.discoverLocal]
            )

        case .cachedIPFailed:
            guard let credentials = state.credentials else {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .missingCredentials
                )
                return (
                    TydomConnectionState(
                        phase: .failed,
                        override: state.override,
                        credentials: nil,
                        selectedGatewayMac: state.selectedGatewayMac,
                        lastDecision: decision,
                        lastError: "Missing gateway credentials",
                        connectedConnection: state.connectedConnection
                    ),
                    [.emitDecision(decision)]
                )
            }
            return (
                TydomConnectionState(
                    phase: .discoveringLocal,
                    override: state.override,
                    credentials: credentials,
                    selectedGatewayMac: credentials.mac,
                    lastDecision: state.lastDecision,
                    lastError: nil,
                    connectedConnection: state.connectedConnection
                ),
                [.discoverLocal]
            )

        case .localDiscoveryFound(let candidates):
            guard let credentials = state.credentials else {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .missingCredentials
                )
                return (
                    TydomConnectionState(
                        phase: .failed,
                        override: state.override,
                        credentials: nil,
                        selectedGatewayMac: state.selectedGatewayMac,
                        lastDecision: decision,
                        lastError: "Missing gateway credentials",
                        pendingLocalCandidates: [],
                        connectedConnection: state.connectedConnection
                    ),
                    [.emitDecision(decision)]
                )
            }

            guard let first = candidates.first else {
                let decision = TydomConnectionState.Decision(
                    mode: .remote(),
                    reason: .localDiscoveryFailed
                )
                return (
                    TydomConnectionState(
                        phase: .connectingRemote,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil,
                        pendingLocalCandidates: [],
                        connectedConnection: state.connectedConnection
                    ),
                    [.emitDecision(decision), .connectRemote]
                )
            }

            let remaining = Array(candidates.dropFirst())
            let decision = TydomConnectionState.Decision(
                mode: .local(host: first.host),
                reason: .localConnected
            )
            return (
                TydomConnectionState(
                    phase: .connectingLocal,
                    override: state.override,
                    credentials: credentials,
                    selectedGatewayMac: credentials.mac,
                    lastDecision: decision,
                    lastError: nil,
                    pendingLocalCandidates: remaining,
                    connectedConnection: state.connectedConnection
                ),
                [.emitDecision(decision), .connectLocal(first.host)]
            )

        case .localConnectResult(let success, let host, let connection):
            if success, let host {
                guard let credentials = state.credentials else {
                    return (
                        TydomConnectionState(
                            phase: .connected,
                            override: state.override,
                            credentials: state.credentials,
                            selectedGatewayMac: state.selectedGatewayMac,
                            lastDecision: state.lastDecision,
                            lastError: nil,
                            pendingLocalCandidates: [],
                            connectedConnection: connection ?? state.connectedConnection
                        ),
                        []
                    )
                }
                let updated = TydomGatewayCredentials(
                    mac: credentials.mac,
                    password: credentials.password,
                    cachedLocalIP: host,
                    updatedAt: credentials.updatedAt
                )
                return (
                    TydomConnectionState(
                        phase: .connected,
                        override: state.override,
                        credentials: updated,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: state.lastDecision,
                        lastError: nil,
                        pendingLocalCandidates: [],
                        connectedConnection: connection ?? state.connectedConnection
                    ),
                    [.saveCredentials(updated)]
                )
            }

            if let next = state.pendingLocalCandidates.first, let credentials = state.credentials {
                let remaining = Array(state.pendingLocalCandidates.dropFirst())
                let decision = TydomConnectionState.Decision(
                    mode: .local(host: next.host),
                    reason: .localConnected
                )
                return (
                    TydomConnectionState(
                        phase: .connectingLocal,
                        override: state.override,
                        credentials: credentials,
                        selectedGatewayMac: credentials.mac,
                        lastDecision: decision,
                        lastError: nil,
                        pendingLocalCandidates: remaining,
                        connectedConnection: state.connectedConnection
                    ),
                    [.emitDecision(decision), .connectLocal(next.host)]
                )
            }

            let decision = TydomConnectionState.Decision(
                mode: .remote(),
                reason: .localFailed
            )
            return (
                TydomConnectionState(
                    phase: .connectingRemote,
                    override: state.override,
                    credentials: state.credentials,
                    selectedGatewayMac: state.selectedGatewayMac,
                    lastDecision: decision,
                    lastError: nil,
                    pendingLocalCandidates: [],
                    connectedConnection: state.connectedConnection
                ),
                [.emitDecision(decision), .connectRemote]
            )

        case .remoteConnectResult(let success, let connection):
            if success {
                return (
                    TydomConnectionState(
                        phase: .connected,
                        override: state.override,
                        credentials: state.credentials,
                        selectedGatewayMac: state.selectedGatewayMac,
                        lastDecision: state.lastDecision,
                        lastError: nil,
                        connectedConnection: connection ?? state.connectedConnection
                    ),
                    []
                )
            }
            let decision = TydomConnectionState.Decision(
                mode: .remote(),
                reason: .remoteFailed
            )
            return (
                TydomConnectionState(
                    phase: .failed,
                    override: state.override,
                    credentials: state.credentials,
                    selectedGatewayMac: state.selectedGatewayMac,
                    lastDecision: decision,
                    lastError: "Remote connection failed",
                    connectedConnection: state.connectedConnection
                ),
                [.emitDecision(decision)]
            )

        case .credentialsSaved(let credentials):
            return (
                TydomConnectionState(
                    phase: state.phase,
                    override: state.override,
                    credentials: credentials,
                    selectedGatewayMac: credentials.mac,
                    lastDecision: state.lastDecision,
                    lastError: nil,
                    connectedConnection: state.connectedConnection
                ),
                []
            )

        case .failure(let message):
            return (
                TydomConnectionState(
                    phase: .failed,
                    override: state.override,
                    credentials: state.credentials,
                    selectedGatewayMac: state.selectedGatewayMac,
                    lastDecision: state.lastDecision,
                    lastError: message,
                    connectedConnection: state.connectedConnection
                ),
                []
            )
        }
    }
}
