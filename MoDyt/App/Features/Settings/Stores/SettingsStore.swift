import Foundation
import Observation

struct SettingsState: Sendable, Equatable {
    var isDisconnecting: Bool
    var errorMessage: String?

    static let initial = SettingsState(isDisconnecting: false, errorMessage: nil)
}

enum SettingsEvent: Sendable {
    case disconnectTapped
    case disconnectFinished(Result<Void, Error>)
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
            state.errorMessage = nil
            effects = [.requestDisconnect]

        case .disconnectFinished(let result):
            state.isDisconnecting = false
            switch result {
            case .success:
                state.errorMessage = nil
            case .failure(let error):
                state.errorMessage = error.localizedDescription
            }
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class SettingsStore {
    struct Dependencies {
        let requestDisconnect: () async throws -> Void
    }

    private(set) var state: SettingsState

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.state = .initial
        self.dependencies = dependencies
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
            Task { [weak self, dependencies] in
                do {
                    try await dependencies.requestDisconnect()
                    self?.send(.disconnectFinished(.success(())))
                } catch {
                    self?.send(.disconnectFinished(.failure(error)))
                }
            }
        }
    }
}
