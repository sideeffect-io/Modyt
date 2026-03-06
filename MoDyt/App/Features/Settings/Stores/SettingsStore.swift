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
        var state: SettingsState = .initial

        mutating func reduce(_ event: SettingsEvent) -> [SettingsEffect] {
            switch event {
            case .disconnectTapped:
                guard !state.isDisconnecting else { return [] }
                state.isDisconnecting = true
                state.didDisconnect = false
                state.errorMessage = nil
                return [.requestDisconnect]

            case .disconnectFinished:
                state.isDisconnecting = false
                state.didDisconnect = true
                state.errorMessage = nil
                return []
            }
        }
    }

    struct Dependencies {
        let requestDisconnect: @Sendable () async -> Void
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: SettingsState {
        stateMachine.state
    }

    private let worker: Worker
    private let disconnectTask = TaskHandle()

    init(dependencies: Dependencies) {
        self.worker = Worker(requestDisconnect: dependencies.requestDisconnect)
    }

    func send(_ event: SettingsEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    func start() {}

    deinit {
        disconnectTask.cancel()
    }

    private func handle(_ effects: [SettingsEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: SettingsEffect) {
        switch effect {
        case .requestDisconnect:
            disconnectTask.task = Task { [weak self, worker] in
                await worker.requestDisconnect()
                self?.receive(.disconnectFinished)
            }
        }
    }

    private func receive(_ event: SettingsEvent) {
        send(event)
    }

    private actor Worker {
        private let requestDisconnectAction: @Sendable () async -> Void

        init(requestDisconnect: @escaping @Sendable () async -> Void) {
            self.requestDisconnectAction = requestDisconnect
        }

        func requestDisconnect() async {
            await requestDisconnectAction()
        }
    }
}
