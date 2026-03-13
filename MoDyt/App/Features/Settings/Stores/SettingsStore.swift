import Foundation
import Observation

enum SettingsConnectionRoute: Sendable, Equatable {
    case local(host: String)
    case remote(host: String)
    case unavailable
}

struct SettingsState: Sendable, Equatable {
    var isDisconnecting: Bool
    var isRefreshingConnectionRoute: Bool
    var didDisconnect: Bool
    var connectionRoute: SettingsConnectionRoute
    var errorMessage: String?

    static let initial = SettingsState(
        isDisconnecting: false,
        isRefreshingConnectionRoute: false,
        didDisconnect: false,
        connectionRoute: .unavailable,
        errorMessage: nil
    )
}

enum SettingsEvent: Sendable {
    case connectionRouteRefreshRequested
    case connectionRouteLoaded(SettingsConnectionRoute)
    case disconnectTapped
    case disconnectFinished
}

enum SettingsEffect: Sendable, Equatable {
    case refreshConnectionRoute
    case requestDisconnect
}

@Observable
@MainActor
final class SettingsStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: SettingsState,
            _ event: SettingsEvent
        ) -> Transition<SettingsState, SettingsEffect> {
            var state = state

            switch event {
            case .connectionRouteRefreshRequested:
                guard !state.isRefreshingConnectionRoute else { return .init(state: state) }
                state.isRefreshingConnectionRoute = true
                return .init(state: state, effects: [.refreshConnectionRoute])

            case .connectionRouteLoaded(let connectionRoute):
                state.isRefreshingConnectionRoute = false
                state.connectionRoute = connectionRoute
                return .init(state: state)

            case .disconnectTapped:
                guard !state.isDisconnecting else { return .init(state: state) }
                state.isDisconnecting = true
                state.didDisconnect = false
                state.errorMessage = nil
                return .init(state: state, effects: [.requestDisconnect])

            case .disconnectFinished:
                state.isDisconnecting = false
                state.isRefreshingConnectionRoute = false
                state.didDisconnect = true
                state.connectionRoute = .unavailable
                state.errorMessage = nil
                return .init(state: state)
            }
        }
    }

    private(set) var state: SettingsState = .initial

    private let refreshConnectionRoute: ReadSettingsConnectionRouteEffectExecutor
    private let requestDisconnect: RequestDisconnectEffectExecutor
    private var connectionRouteTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?

    init(
        refreshConnectionRoute: ReadSettingsConnectionRouteEffectExecutor,
        requestDisconnect: RequestDisconnectEffectExecutor
    ) {
        self.refreshConnectionRoute = refreshConnectionRoute
        self.requestDisconnect = requestDisconnect
    }

    func send(_ event: SettingsEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    func start() {}

    isolated deinit {
        connectionRouteTask?.cancel()
        disconnectTask?.cancel()
    }

    private func handle(_ effects: [SettingsEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: SettingsEffect) {
        switch effect {
        case .refreshConnectionRoute:
            replaceTask(
                &connectionRouteTask,
                with: makeTrackedEventTask(
                    operation: { [refreshConnectionRoute] in
                        await refreshConnectionRoute()
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    },
                    onFinish: { [weak self] in
                        self?.connectionRouteTask = nil
                    }
                )
            )

        case .requestDisconnect:
            replaceTask(
                &disconnectTask,
                with: makeTrackedEventTask(
                    operation: { [requestDisconnect] in
                        await requestDisconnect()
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    },
                    onFinish: { [weak self] in
                        self?.disconnectTask = nil
                    }
                )
            )
        }
    }

    private func receive(_ event: SettingsEvent) {
        send(event)
    }
}
