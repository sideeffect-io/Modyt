import Foundation
import Observation

struct ScenesState: Sendable, Equatable {
    var scenes: [SceneRecord]

    static let initial = ScenesState(scenes: [])
}

enum ScenesEvent: Sendable {
    case onAppear
    case scenesUpdated([SceneRecord])
    case refreshRequested
    case toggleFavorite(String)
}

enum ScenesEffect: Sendable, Equatable {
    case startObservingScenes
    case refreshAll
    case toggleFavorite(String)
}

enum ScenesReducer {
    static func reduce(state: ScenesState, event: ScenesEvent) -> (ScenesState, [ScenesEffect]) {
        var state = state
        var effects: [ScenesEffect] = []

        switch event {
        case .onAppear:
            effects = [.startObservingScenes]

        case .scenesUpdated(let scenes):
            state.scenes = scenes

        case .refreshRequested:
            effects = [.refreshAll]

        case .toggleFavorite(let uniqueId):
            effects = [.toggleFavorite(uniqueId)]
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class ScenesStore {
    struct Dependencies {
        let observeScenes: @Sendable () async -> AsyncStream<[SceneRecord]>
        let toggleFavorite: @Sendable (String) async -> Void
        let refreshAll: @Sendable () async -> Void
    }

    private(set) var state: ScenesState

    private let sceneTask = TaskHandle()
    private let worker: Worker

    init(dependencies: Dependencies) {
        self.state = .initial
        self.worker = Worker(
            observeScenes: dependencies.observeScenes,
            toggleFavorite: dependencies.toggleFavorite,
            refreshAll: dependencies.refreshAll
        )
    }

    func send(_ event: ScenesEvent) {
        let (nextState, effects) = ScenesReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [ScenesEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: ScenesEffect) {
        switch effect {
        case .startObservingScenes:
            guard sceneTask.task == nil else { return }
            sceneTask.task = Task { [weak self, worker] in
                await worker.observeScenes { [weak self] scenes in
                    await self?.send(.scenesUpdated(scenes))
                }
            }

        case .toggleFavorite(let uniqueId):
            Task { [worker] in
                await worker.toggleFavorite(uniqueId)
            }

        case .refreshAll:
            Task { [worker] in
                await worker.refreshAll()
            }
        }
    }

    private actor Worker {
        private let observeScenesSource: @Sendable () async -> AsyncStream<[SceneRecord]>
        private let toggleFavoriteAction: @Sendable (String) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeScenes: @escaping @Sendable () async -> AsyncStream<[SceneRecord]>,
            toggleFavorite: @escaping @Sendable (String) async -> Void,
            refreshAll: @escaping @Sendable () async -> Void
        ) {
            self.observeScenesSource = observeScenes
            self.toggleFavoriteAction = toggleFavorite
            self.refreshAllAction = refreshAll
        }

        func observeScenes(
            onUpdate: @escaping @Sendable ([SceneRecord]) async -> Void
        ) async {
            let stream = await observeScenesSource()
            for await scenes in stream {
                guard !Task.isCancelled else { return }
                let sorted = scenes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                await onUpdate(sorted)
            }
        }

        func toggleFavorite(_ uniqueId: String) async {
            await toggleFavoriteAction(uniqueId)
        }

        func refreshAll() async {
            await refreshAllAction()
        }
    }
}

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
