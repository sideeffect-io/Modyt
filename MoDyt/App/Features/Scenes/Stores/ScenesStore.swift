import Foundation
import Observation

struct ScenesState: Sendable, Equatable {
    var scenes: [Scene]

    static let initial = ScenesState(scenes: [])
}

enum ScenesEvent: Sendable {
    case onAppear
    case scenesUpdated([Scene])
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
        var state: ScenesState = .initial

        mutating func reduce(_ event: ScenesEvent) -> [ScenesEffect] {
            switch event {
            case .onAppear:
                return [.startObservingScenes]

            case .scenesUpdated(let scenes):
                state.scenes = scenes
                return []

            case .refreshRequested:
                return [.refreshAll]

            case .toggleFavorite(let uniqueId):
                return [.toggleFavorite(uniqueId)]
            }
        }
    }

    struct Dependencies {
        let observeScenes: @Sendable () async -> any AsyncSequence<[Scene], Never> & Sendable
        let toggleFavorite: @Sendable (String) async -> Void
        let refreshAll: @Sendable () async -> Void
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: ScenesState {
        stateMachine.state
    }

    private let sceneTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    init(dependencies: Dependencies) {
        self.worker = Worker(
            observeScenes: dependencies.observeScenes,
            toggleFavorite: dependencies.toggleFavorite,
            refreshAll: dependencies.refreshAll
        )
    }

    func send(_ event: ScenesEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    deinit {
        sceneTask.cancel()
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
            let taskHandle = sceneTask
            sceneTask.task = Task { [weak self, worker, weak taskHandle] in
                defer {
                    Task { @MainActor [weak taskHandle] in
                        taskHandle?.task = nil
                    }
                }
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
        private let observeScenesSource: @Sendable () async -> any AsyncSequence<[Scene], Never> & Sendable
        private let toggleFavoriteAction: @Sendable (String) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeScenes: @escaping @Sendable () async -> any AsyncSequence<[Scene], Never> & Sendable,
            toggleFavorite: @escaping @Sendable (String) async -> Void,
            refreshAll: @escaping @Sendable () async -> Void
        ) {
            self.observeScenesSource = observeScenes
            self.toggleFavoriteAction = toggleFavorite
            self.refreshAllAction = refreshAll
        }

        func observeScenes(
            onUpdate: @escaping @Sendable ([Scene]) async -> Void
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
