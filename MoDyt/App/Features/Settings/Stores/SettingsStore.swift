import Foundation
import Observation

struct SettingsState: Sendable, Equatable {
    var isDisconnecting: Bool
    var didDisconnect: Bool
    var errorMessage: String?

    static let initial = SettingsState(
        isDisconnecting: false,
        didDisconnect: false,
        errorMessage: nil
    )
}

enum SettingsEvent: Sendable {
    case disconnectTapped
    case disconnectFinished
}

enum SettingsEffect: Sendable, Equatable {
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
            case .disconnectTapped:
                guard !state.isDisconnecting else { return .init(state: state) }
                state.isDisconnecting = true
                state.didDisconnect = false
                state.errorMessage = nil
                return .init(state: state, effects: [.requestDisconnect])

            case .disconnectFinished:
                state.isDisconnecting = false
                state.didDisconnect = true
                state.errorMessage = nil
                return .init(state: state)
            }
        }
    }

    private(set) var state: SettingsState = .initial

    private let requestDisconnect: RequestDisconnectEffectExecutor
    private var disconnectTask: Task<Void, Never>?

    init(requestDisconnect: RequestDisconnectEffectExecutor) {
        self.requestDisconnect = requestDisconnect
    }

    func send(_ event: SettingsEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    func start() {}

    isolated deinit {
        disconnectTask?.cancel()
    }

    private func handle(_ effects: [SettingsEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: SettingsEffect) {
        switch effect {
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
