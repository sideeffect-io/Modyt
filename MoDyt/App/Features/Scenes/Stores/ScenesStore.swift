import Foundation
import Observation

struct ScenesState: Sendable, Equatable {
    var scenes: [Scene]

    static let initial = ScenesState(scenes: [])
}

enum ScenesEvent: Sendable {
    case onAppear
    case scenesObserved([Scene])
    case refreshRequested
    case toggleFavorite(String)
}

enum ScenesEffect: Sendable, Equatable {
    case startObservingScenes
    case refreshAll
    case toggleFavorite(String)
}

@Observable
@MainActor
final class ScenesStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: ScenesState,
            _ event: ScenesEvent
        ) -> Transition<ScenesState, ScenesEffect> {
            var state = state

            switch event {
            case .onAppear:
                return .init(state: state, effects: [.startObservingScenes])

            case .scenesObserved(let scenes):
                state.scenes = ScenesStoreProjector.scenes(from: scenes)
                return .init(state: state)

            case .refreshRequested:
                return .init(state: state, effects: [.refreshAll])

            case .toggleFavorite(let uniqueId):
                return .init(state: state, effects: [.toggleFavorite(uniqueId)])
            }
        }
    }

    private(set) var state: ScenesState = .initial

    private let observeScenes: ObserveScenesEffectExecutor
    private let toggleFavorite: ToggleSceneFavoriteEffectExecutor
    private let refreshAll: RefreshScenesEffectExecutor
    private var sceneTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        observeScenes: ObserveScenesEffectExecutor,
        toggleFavorite: ToggleSceneFavoriteEffectExecutor,
        refreshAll: RefreshScenesEffectExecutor
    ) {
        self.observeScenes = observeScenes
        self.toggleFavorite = toggleFavorite
        self.refreshAll = refreshAll
    }

    func send(_ event: ScenesEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    isolated deinit {
        sceneTask?.cancel()
    }

    private func handle(_ effects: [ScenesEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: ScenesEffect) {
        switch effect {
        case .startObservingScenes:
            guard sceneTask == nil else { return }
            replaceTask(
                &sceneTask,
                with: makeTrackedStreamTask(
                    operation: { [observeScenes] in
                        await observeScenes()
                    },
                    onEvent: { [weak self] event in
                        self?.send(event)
                    },
                    onFinish: { [weak self] in
                        self?.sceneTask = nil
                    }
                )
            )

        case .toggleFavorite(let uniqueId):
            launchFireAndForgetTask { [toggleFavorite] in
                await toggleFavorite(uniqueId)
            }

        case .refreshAll:
            launchFireAndForgetTask { [refreshAll] in
                await refreshAll()
            }
        }
    }
}

private enum ScenesStoreProjector {
    nonisolated static func scenes(from scenes: [Scene]) -> [Scene] {
        scenes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
