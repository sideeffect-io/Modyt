import Foundation
import Observation
import DeltaDoreClient

struct LoginState: Sendable, Equatable {
    var email: String = ""
    var password: String = ""
    var sites: [DeltaDoreClient.Site] = []
    var selectedSiteIndex: Int? = nil
    var isLoadingSites: Bool = false
    var isConnecting: Bool = false
    var errorMessage: String? = nil

    var canLoadSites: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !password.isEmpty
    }

    var canConnect: Bool {
        selectedSiteIndex != nil && !isConnecting
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

enum AuthenticationEvent: Sendable {
    case onAppear
    case flowInspected(DeltaDoreClient.ConnectionFlowStatus)
    case loginEmailChanged(String)
    case loginPasswordChanged(String)
    case loadSitesTapped
    case sitesLoaded(Result<[DeltaDoreClient.Site], Error>)
    case siteSelected(Int)
    case connectTapped
    case connectionSucceeded(TydomConnection)
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
    case authenticated(connection: TydomConnection)
}

enum AuthenticationReducer {
    static func reduce(
        state: AuthenticationState,
        event: AuthenticationEvent
    ) -> (AuthenticationState, [AuthenticationEffect]) {
        var state = state
        var effects: [AuthenticationEffect] = []

        switch event {
        case .onAppear, .retryTapped:
            state.phase = .bootstrapping
            effects = [.inspectFlow]

        case .flowInspected(let flow):
            switch flow {
            case .connectWithStoredCredentials:
                state.phase = .connecting
                effects = [.connectStored]
            case .connectWithNewCredentials:
                state.phase = .login(LoginState())
            }

        case .loginEmailChanged(let email):
            if case .login(var login) = state.phase {
                login.email = email
                login.errorMessage = nil
                state.phase = .login(login)
            }

        case .loginPasswordChanged(let password):
            if case .login(var login) = state.phase {
                login.password = password
                login.errorMessage = nil
                state.phase = .login(login)
            }

        case .loadSitesTapped:
            if case .login(var login) = state.phase, login.canLoadSites {
                login.isLoadingSites = true
                login.errorMessage = nil
                state.phase = .login(login)
                effects = [.listSites(email: login.email, password: login.password)]
            }

        case .sitesLoaded(let result):
            if case .login(var login) = state.phase {
                login.isLoadingSites = false
                switch result {
                case .success(let sites):
                    login.sites = sites
                    login.selectedSiteIndex = sites.count == 1 ? 0 : nil
                    login.errorMessage = nil
                case .failure(let error):
                    login.errorMessage = error.localizedDescription
                }
                state.phase = .login(login)
            }

        case .siteSelected(let index):
            if case .login(var login) = state.phase {
                login.selectedSiteIndex = index
                login.errorMessage = nil
                state.phase = .login(login)
            }

        case .connectTapped:
            if case .login(var login) = state.phase, login.canConnect {
                login.isConnecting = true
                login.errorMessage = nil
                state.phase = .login(login)
                effects = [.connectNew(email: login.email, password: login.password, siteIndex: login.selectedSiteIndex)]
            }

        case .connectionSucceeded:
            state.phase = .connecting

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
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class AuthenticationStore {
    private(set) var state: AuthenticationState

    var onDelegateEvent: @MainActor (AuthenticationDelegateEvent) -> Void

    private let environment: AppEnvironment

    init(
        environment: AppEnvironment,
        onDelegateEvent: @escaping @MainActor (AuthenticationDelegateEvent) -> Void = { _ in }
    ) {
        self.environment = environment
        self.state = .initial
        self.onDelegateEvent = onDelegateEvent
    }

    func send(_ event: AuthenticationEvent) {
        let (next, effects) = AuthenticationReducer.reduce(state: state, event: event)
        state = next

        switch event {
        case .connectionSucceeded(let connection):
            onDelegateEvent(.authenticated(connection: connection))
        default:
            break
        }

        handle(effects)
    }

    private func handle(_ effects: [AuthenticationEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: AuthenticationEffect) {
        switch effect {
        case .inspectFlow:
            Task { [environment] in
                let flow = await environment.client.inspectConnectionFlow()
                await MainActor.run {
                    self.send(.flowInspected(flow))
                }
            }

        case .connectStored:
            Task { [environment] in
                do {
                    let session = try await environment.client.connectWithStoredCredentials(options: .init())
                    await MainActor.run {
                        self.send(.connectionSucceeded(session.connection))
                    }
                } catch {
                    await MainActor.run {
                        self.send(.connectionFailed(error.localizedDescription))
                    }
                }
            }

        case .listSites(let email, let password):
            Task { [environment] in
                do {
                    let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                    let sites = try await environment.client.listSites(cloudCredentials: credentials)
                    await MainActor.run {
                        self.send(.sitesLoaded(.success(sites)))
                    }
                } catch {
                    await MainActor.run {
                        self.send(.sitesLoaded(.failure(error)))
                    }
                }
            }

        case .connectNew(let email, let password, let siteIndex):
            Task { [environment] in
                do {
                    let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                    let session = try await environment.client.connectWithNewCredentials(
                        options: .init(mode: .auto(cloudCredentials: credentials)),
                        selectSiteIndex: { _ in siteIndex }
                    )
                    await MainActor.run {
                        self.send(.connectionSucceeded(session.connection))
                    }
                } catch {
                    await MainActor.run {
                        self.send(.connectionFailed(error.localizedDescription))
                    }
                }
            }
        }
    }
}
