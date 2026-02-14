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

struct SettingsStoreError: LocalizedError, Sendable, Equatable {
    let message: String

    var errorDescription: String? { message }
}

enum SettingsEvent: Sendable {
    case disconnectTapped
    case disconnectFinished(Result<Void, SettingsStoreError>)
}

enum SettingsEffect: Sendable, Equatable {
    case requestDisconnect
}

enum SettingsReducer {
    static func reduce(state: SettingsState, event: SettingsEvent) -> (SettingsState, [SettingsEffect]) {
        var state = state
        var effects: [SettingsEffect] = []

        switch event {
        case .disconnectTapped:
            guard !state.isDisconnecting else { return (state, effects) }
            state.isDisconnecting = true
            state.didDisconnect = false
            state.errorMessage = nil
            effects = [.requestDisconnect]

        case .disconnectFinished(let result):
            state.isDisconnecting = false
            switch result {
            case .success:
                state.didDisconnect = true
                state.errorMessage = nil
            case .failure(let error):
                state.didDisconnect = false
                state.errorMessage = error.message
            }
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class SettingsStore {
    struct Dependencies {
        let requestDisconnect: @Sendable () async -> Result<Void, SettingsStoreError>
    }

    private(set) var state: SettingsState

    private let worker: Worker

    init(dependencies: Dependencies) {
        self.state = .initial
        self.worker = Worker(requestDisconnect: dependencies.requestDisconnect)
    }

    func send(_ event: SettingsEvent) {
        let (nextState, effects) = SettingsReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [SettingsEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: SettingsEffect) {
        switch effect {
        case .requestDisconnect:
            Task { [weak self, worker] in
                let result = await worker.requestDisconnect()
                self?.receive(.disconnectFinished(result))
            }
        }
    }

    private func receive(_ event: SettingsEvent) {
        send(event)
    }

    private actor Worker {
        private let requestDisconnectAction: @Sendable () async -> Result<Void, SettingsStoreError>

        init(requestDisconnect: @escaping @Sendable () async -> Result<Void, SettingsStoreError>) {
            self.requestDisconnectAction = requestDisconnect
        }

        func requestDisconnect() async -> Result<Void, SettingsStoreError> {
            await requestDisconnectAction()
        }
    }
}
