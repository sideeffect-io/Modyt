import Foundation
import Observation

struct LoginState: Sendable, Equatable {
    var email: String = ""
    var password: String = ""
    var sites: [AuthenticationSite] = []
    var selectedSiteID: String? = nil
    var isLoadingSites: Bool = false
    var isConnecting: Bool = false
    var errorMessage: String? = nil

    var selectedSiteIndex: Int? {
        guard let selectedSiteID else { return nil }
        return sites.firstIndex { $0.id == selectedSiteID }
    }

    var canLoadSites: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    var canConnect: Bool {
        selectedSiteID != nil && !isConnecting
    }
}

enum AuthenticationPhase: Sendable, Equatable {
    case bootstrapping
    case login(LoginState)
    case connecting
    case error(String)
}

struct AuthenticationState: Sendable, Equatable {
    var phase: AuthenticationPhase

    static let initial = AuthenticationState(phase: .bootstrapping)
}

struct AuthenticationStoreError: LocalizedError, Sendable, Equatable {
    let message: String

    var errorDescription: String? { message }
}

enum AuthenticationEvent: Sendable {
    case onAppear
    case flowInspected(AuthenticationFlowStatus)
    case loginEmailChanged(String)
    case loginPasswordChanged(String)
    case loadSitesTapped
    case sitesLoaded(Result<[AuthenticationSite], AuthenticationStoreError>)
    case siteSelected(String)
    case connectTapped
    case connectionSucceeded
    case connectionFailed(String)
    case retryTapped
}

enum AuthenticationEffect: Sendable, Equatable {
    case inspectFlow
    case connectStored
    case listSites(email: String, password: String)
    case connectNew(email: String, password: String, siteIndex: Int?)
}

enum AuthenticationDelegateEvent {
    case authenticated
}

@Observable
@MainActor
final class AuthenticationStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: AuthenticationState,
            _ event: AuthenticationEvent
        ) -> Transition<AuthenticationState, AuthenticationEffect> {
            var state = state

            switch event {
            case .onAppear, .retryTapped:
                state.phase = .bootstrapping
                return .init(state: state, effects: [.inspectFlow])

            case .flowInspected(let flow):
                switch flow {
                case .connectWithStoredCredentials:
                    state.phase = .connecting
                    return .init(state: state, effects: [.connectStored])
                case .connectWithNewCredentials:
                    state.phase = .login(LoginState())
                    return .init(state: state)
                }

            case .loginEmailChanged(let email):
                if case .login(var login) = state.phase {
                    login.email = email
                    login.errorMessage = nil
                    state.phase = .login(login)
                }
                return .init(state: state)

            case .loginPasswordChanged(let password):
                if case .login(var login) = state.phase {
                    login.password = password
                    login.errorMessage = nil
                    state.phase = .login(login)
                }
                return .init(state: state)

            case .loadSitesTapped:
                if case .login(var login) = state.phase, login.canLoadSites {
                    login.isLoadingSites = true
                    login.errorMessage = nil
                    state.phase = .login(login)
                    return .init(
                        state: state,
                        effects: [.listSites(email: login.email, password: login.password)]
                    )
                }
                return .init(state: state)

            case .sitesLoaded(let result):
                if case .login(var login) = state.phase {
                    login.isLoadingSites = false
                    switch result {
                    case .success(let sites):
                        login.sites = sites
                        login.selectedSiteID = Self.selectedSiteID(
                            from: sites,
                            preferred: login.selectedSiteID
                        )
                        login.errorMessage = nil
                    case .failure(let error):
                        login.errorMessage = error.message
                    }
                    state.phase = .login(login)
                }
                return .init(state: state)

            case .siteSelected(let siteID):
                if case .login(var login) = state.phase {
                    login.selectedSiteID = login.sites.contains(where: { $0.id == siteID })
                        ? siteID
                        : nil
                    login.errorMessage = nil
                    state.phase = .login(login)
                }
                return .init(state: state)

            case .connectTapped:
                if case .login(var login) = state.phase, login.canConnect {
                    login.isConnecting = true
                    login.errorMessage = nil
                    state.phase = .login(login)
                    return .init(
                        state: state,
                        effects: [
                            .connectNew(
                                email: login.email,
                                password: login.password,
                                siteIndex: login.selectedSiteIndex
                            )
                        ]
                    )
                }
                return .init(state: state)

            case .connectionSucceeded:
                state.phase = .connecting
                return .init(state: state)

            case .connectionFailed(let message):
                switch state.phase {
                case .login(var login):
                    login.isLoadingSites = false
                    login.isConnecting = false
                    login.errorMessage = message
                    state.phase = .login(login)
                default:
                    state.phase = .error(message)
                }
                return .init(state: state)
            }
        }

        private static func selectedSiteID(
            from sites: [AuthenticationSite],
            preferred: String?
        ) -> String? {
            if sites.count == 1 {
                return sites.first?.id
            }

            if let preferred, sites.contains(where: { $0.id == preferred }) {
                return preferred
            }

            return nil
        }
    }

    private(set) var state: AuthenticationState = .initial

    var onDelegateEvent: @MainActor (AuthenticationDelegateEvent) -> Void

    private let inspectFlow: InspectAuthenticationFlowEffectExecutor
    private let connectStored: ConnectStoredAuthenticationEffectExecutor
    private let listSites: ListAuthenticationSitesEffectExecutor
    private let connectNew: ConnectNewAuthenticationEffectExecutor
    private var effectTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        inspectFlow: InspectAuthenticationFlowEffectExecutor,
        connectStored: ConnectStoredAuthenticationEffectExecutor,
        listSites: ListAuthenticationSitesEffectExecutor,
        connectNew: ConnectNewAuthenticationEffectExecutor,
        onDelegateEvent: @escaping @MainActor (AuthenticationDelegateEvent) -> Void = { _ in }
    ) {
        self.onDelegateEvent = onDelegateEvent
        self.inspectFlow = inspectFlow
        self.connectStored = connectStored
        self.listSites = listSites
        self.connectNew = connectNew
    }

    func send(_ event: AuthenticationEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state

        switch event {
        case .connectionSucceeded:
            onDelegateEvent(.authenticated)
        default:
            break
        }

        handle(transition.effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    isolated deinit {
        effectTask?.cancel()
    }

    private func handle(_ effects: [AuthenticationEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: AuthenticationEffect) {
        switch effect {
        case .inspectFlow:
            replaceTask(
                &effectTask,
                with: makeTrackedEventTask(
                    operation: { [inspectFlow] in
                        await inspectFlow()
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    }
                )
            )

        case .connectStored:
            replaceTask(
                &effectTask,
                with: makeTrackedEventTask(
                    operation: { [connectStored] in
                        await connectStored()
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    }
                )
            )

        case .listSites(let email, let password):
            replaceTask(
                &effectTask,
                with: makeTrackedEventTask(
                    operation: { [listSites] in
                        await listSites(
                            email: email,
                            password: password
                        )
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    }
                )
            )

        case .connectNew(let email, let password, let siteIndex):
            replaceTask(
                &effectTask,
                with: makeTrackedEventTask(
                    operation: { [connectNew] in
                        await connectNew(
                            email: email,
                            password: password,
                            siteIndex: siteIndex
                        )
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    }
                )
            )
        }
    }

    private func receive(_ event: AuthenticationEvent) {
        send(event)
    }
}
