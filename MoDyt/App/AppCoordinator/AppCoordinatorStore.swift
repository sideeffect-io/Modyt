import Foundation
import Observation

struct AppCoordinatorState {
    enum Route {
        case authentication(AuthenticationStore)
        case runtime(RuntimeStore)
    }

    var route: Route
    var isAppActive: Bool
}

enum AppCoordinatorEvent {
    case onAppear
    case setAppActive(Bool)
    case authenticationDelegateEvent(AuthenticationDelegateEvent)
    case runtimeDelegateEvent(RuntimeDelegateEvent)
}

@Observable
@MainActor
final class AppCoordinatorStore {
    private(set) var state: AppCoordinatorState

    private let environment: AppEnvironment

    init(environment: AppEnvironment) {
        self.environment = environment

        let authenticationStore = AuthenticationStore(environment: environment)
        self.state = AppCoordinatorState(
            route: .authentication(authenticationStore),
            isAppActive: true
        )

        authenticationStore.onDelegateEvent = { [weak self] delegateEvent in
            self?.send(.authenticationDelegateEvent(delegateEvent))
        }
    }

    func send(_ event: AppCoordinatorEvent) {
        switch event {
        case .onAppear:
            switch state.route {
            case .authentication(let authenticationStore):
                authenticationStore.send(.onAppear)
            case .runtime(let runtimeStore):
                runtimeStore.send(.onStart)
            }

        case .setAppActive(let isAppActive):
            state.isAppActive = isAppActive
            if case .runtime(let runtimeStore) = state.route {
                runtimeStore.send(.setAppActive(isAppActive))
            }

        case .authenticationDelegateEvent(let delegateEvent):
            handleAuthenticationDelegateEvent(delegateEvent)

        case .runtimeDelegateEvent(let delegateEvent):
            handleRuntimeDelegateEvent(delegateEvent)
        }
    }

    private func handleAuthenticationDelegateEvent(_ delegateEvent: AuthenticationDelegateEvent) {
        guard case .authentication = state.route else { return }

        switch delegateEvent {
        case .authenticated(let connection):
            let runtimeStore = RuntimeStore(environment: environment, connection: connection)
            runtimeStore.onDelegateEvent = { [weak self] delegateEvent in
                self?.send(.runtimeDelegateEvent(delegateEvent))
            }
            state.route = .runtime(runtimeStore)
            runtimeStore.send(.onStart)
            runtimeStore.send(.setAppActive(state.isAppActive))
        }
    }

    private func handleRuntimeDelegateEvent(_ delegateEvent: RuntimeDelegateEvent) {
        guard case .runtime = state.route else { return }

        switch delegateEvent {
        case .didDisconnect:
            let authenticationStore = AuthenticationStore(environment: environment)
            authenticationStore.onDelegateEvent = { [weak self] delegateEvent in
                self?.send(.authenticationDelegateEvent(delegateEvent))
            }
            state.route = .authentication(authenticationStore)
            authenticationStore.send(.onAppear)
        }
    }
}
