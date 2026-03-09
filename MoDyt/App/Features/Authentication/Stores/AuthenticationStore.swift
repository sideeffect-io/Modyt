import Foundation
import Observation
import DeltaDoreClient

struct LoginState: Sendable, Equatable {
    var email: String = ""
    var password: String = ""
    var sites: [DeltaDoreClient.Site] = []
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
    case flowInspected(DeltaDoreClient.ConnectionFlowStatus)
    case loginEmailChanged(String)
    case loginPasswordChanged(String)
    case loadSitesTapped
    case sitesLoaded(Result<[DeltaDoreClient.Site], AuthenticationStoreError>)
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
        var state: AuthenticationState = .initial

        mutating func reduce(_ event: AuthenticationEvent) -> [AuthenticationEffect] {
            switch event {
            case .onAppear, .retryTapped:
                state.phase = .bootstrapping
                return [.inspectFlow]

            case .flowInspected(let flow):
                switch flow {
                case .connectWithStoredCredentials:
                    state.phase = .connecting
                    return [.connectStored]
                case .connectWithNewCredentials:
                    state.phase = .login(LoginState())
                    return []
                }

            case .loginEmailChanged(let email):
                if case .login(var login) = state.phase {
                    login.email = email
                    login.errorMessage = nil
                    state.phase = .login(login)
                }
                return []

            case .loginPasswordChanged(let password):
                if case .login(var login) = state.phase {
                    login.password = password
                    login.errorMessage = nil
                    state.phase = .login(login)
                }
                return []

            case .loadSitesTapped:
                if case .login(var login) = state.phase, login.canLoadSites {
                    login.isLoadingSites = true
                    login.errorMessage = nil
                    state.phase = .login(login)
                    return [.listSites(email: login.email, password: login.password)]
                }
                return []

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
                return []

            case .siteSelected(let siteID):
                if case .login(var login) = state.phase {
                    login.selectedSiteID = login.sites.contains(where: { $0.id == siteID })
                        ? siteID
                        : nil
                    login.errorMessage = nil
                    state.phase = .login(login)
                }
                return []

            case .connectTapped:
                if case .login(var login) = state.phase, login.canConnect {
                    login.isConnecting = true
                    login.errorMessage = nil
                    state.phase = .login(login)
                    return [
                        .connectNew(
                            email: login.email,
                            password: login.password,
                            siteIndex: login.selectedSiteIndex
                        )
                    ]
                }
                return []

            case .connectionSucceeded:
                state.phase = .connecting
                return []

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
                return []
            }
        }

        private static func selectedSiteID(
            from sites: [DeltaDoreClient.Site],
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

    struct Dependencies {
        let inspectFlow: @Sendable () async -> DeltaDoreClient.ConnectionFlowStatus
        let connectStored: @Sendable () async throws -> Void
        let listSites: @Sendable (String, String) async throws -> [DeltaDoreClient.Site]
        let connectNew: @Sendable (String, String, Int?) async throws -> Void
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: AuthenticationState {
        stateMachine.state
    }

    var onDelegateEvent: @MainActor (AuthenticationDelegateEvent) -> Void

    private let worker: Worker
    private let effectTask = TaskHandle()
    private var hasStarted = false

    init(
        dependencies: Dependencies,
        onDelegateEvent: @escaping @MainActor (AuthenticationDelegateEvent) -> Void = { _ in }
    ) {
        self.onDelegateEvent = onDelegateEvent
        self.worker = Worker(
            inspectFlow: dependencies.inspectFlow,
            connectStored: dependencies.connectStored,
            listSites: dependencies.listSites,
            connectNew: dependencies.connectNew
        )
    }

    func send(_ event: AuthenticationEvent) {
        let effects = stateMachine.reduce(event)

        switch event {
        case .connectionSucceeded:
            onDelegateEvent(.authenticated)
        default:
            break
        }

        handle(effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    deinit {
        effectTask.cancel()
    }

    private func handle(_ effects: [AuthenticationEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: AuthenticationEffect) {
        switch effect {
        case .inspectFlow:
            effectTask.task = Task { [weak self, worker] in
                let flow = await worker.inspectFlow()
                guard !Task.isCancelled else { return }
                self?.receive(.flowInspected(flow))
            }

        case .connectStored:
            effectTask.task = Task { [weak self, worker] in
                if let message = await worker.connectStored() {
                    guard !Task.isCancelled else { return }
                    self?.receive(.connectionFailed(message))
                } else {
                    guard !Task.isCancelled else { return }
                    self?.receive(.connectionSucceeded)
                }
            }

        case .listSites(let email, let password):
            effectTask.task = Task { [weak self, worker] in
                let result = await worker.listSites(email: email, password: password)
                guard !Task.isCancelled else { return }
                self?.receive(.sitesLoaded(result))
            }

        case .connectNew(let email, let password, let siteIndex):
            effectTask.task = Task { [weak self, worker] in
                if let message = await worker.connectNew(email: email, password: password, siteIndex: siteIndex) {
                    guard !Task.isCancelled else { return }
                    self?.receive(.connectionFailed(message))
                } else {
                    guard !Task.isCancelled else { return }
                    self?.receive(.connectionSucceeded)
                }
            }
        }
    }

    private func receive(_ event: AuthenticationEvent) {
        send(event)
    }

    private actor Worker {
        private let inspectFlowAction: @Sendable () async -> DeltaDoreClient.ConnectionFlowStatus
        private let connectStoredAction: @Sendable () async throws -> Void
        private let listSitesAction: @Sendable (String, String) async throws -> [DeltaDoreClient.Site]
        private let connectNewAction: @Sendable (String, String, Int?) async throws -> Void

        init(
            inspectFlow: @escaping @Sendable () async -> DeltaDoreClient.ConnectionFlowStatus,
            connectStored: @escaping @Sendable () async throws -> Void,
            listSites: @escaping @Sendable (String, String) async throws -> [DeltaDoreClient.Site],
            connectNew: @escaping @Sendable (String, String, Int?) async throws -> Void
        ) {
            self.inspectFlowAction = inspectFlow
            self.connectStoredAction = connectStored
            self.listSitesAction = listSites
            self.connectNewAction = connectNew
        }

        func inspectFlow() async -> DeltaDoreClient.ConnectionFlowStatus {
            await inspectFlowAction()
        }

        func connectStored() async -> String? {
            do {
                try await connectStoredAction()
                return nil
            } catch {
                return error.localizedDescription
            }
        }

        func listSites(email: String, password: String) async -> Result<[DeltaDoreClient.Site], AuthenticationStoreError> {
            do {
                let sites = try await listSitesAction(email, password)
                return .success(sites)
            } catch {
                return .failure(AuthenticationStoreError(message: error.localizedDescription))
            }
        }

        func connectNew(email: String, password: String, siteIndex: Int?) async -> String? {
            do {
                try await connectNewAction(email, password, siteIndex)
                return nil
            } catch {
                return error.localizedDescription
            }
        }
    }
}
