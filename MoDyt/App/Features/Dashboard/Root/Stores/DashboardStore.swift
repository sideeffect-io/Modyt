import Foundation
import Observation
import DeltaDoreClient

struct DashboardState: Sendable, Equatable {
    var favoriteDevices: [DashboardDeviceDescription]

    static let initial = DashboardState(favoriteDevices: [])
}

enum DashboardEvent: Sendable {
    case onAppear
    case favoritesUpdated([DashboardDeviceDescription])
    case refreshRequested
    case reorderFavorite(String, String)
}

enum DashboardEffect: Sendable, Equatable {
    case startObservingFavorites
    case refreshAll
    case reorderFavorite(String, String)
}

enum DashboardReducer {
    static func reduce(state: DashboardState, event: DashboardEvent) -> (DashboardState, [DashboardEffect]) {
        var state = state
        var effects: [DashboardEffect] = []

        switch event {
        case .onAppear:
            effects = [.startObservingFavorites]

        case .favoritesUpdated(let favoriteDevices):
            state.favoriteDevices = favoriteDevices

        case .refreshRequested:
            effects = [.refreshAll]

        case .reorderFavorite(let sourceId, let targetId):
            effects = [.reorderFavorite(sourceId, targetId)]
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class DashboardStore {
    struct Dependencies {
        let observeFavorites: @Sendable () async -> any AsyncSequence<[DashboardDeviceDescription], Never> & Sendable
        let reorderFavorite: @Sendable (String, String) async -> Void
        let refreshAll: @Sendable () async -> Void
    }

    private(set) var state: DashboardState

    private let favoritesTask = TaskHandle()
    private let worker: Worker

    init(dependencies: Dependencies) {
        self.state = .initial
        self.worker = Worker(
            observeFavorites: dependencies.observeFavorites,
            reorderFavorite: dependencies.reorderFavorite,
            refreshAll: dependencies.refreshAll
        )
    }

    func send(_ event: DashboardEvent) {
        let (nextState, effects) = DashboardReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [DashboardEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: DashboardEffect) {
        switch effect {
        case .startObservingFavorites:
            guard favoritesTask.task == nil else { return }
            favoritesTask.task = Task { [weak self, worker] in
                await worker.observeFavorites { [weak self] favoriteDevices in
                    await self?.send(.favoritesUpdated(favoriteDevices))
                }
            }

        case .refreshAll:
            Task { [worker] in
                await worker.refreshAll()
            }

        case .reorderFavorite(let sourceId, let targetId):
            Task { [worker] in
                await worker.reorderFavorite(sourceId: sourceId, targetId: targetId)
            }
        }
    }

    private actor Worker {
        private let observeFavoritesSource: @Sendable () async -> any AsyncSequence<[DashboardDeviceDescription], Never> & Sendable
        private let reorderFavoriteAction: @Sendable (String, String) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeFavorites: @escaping @Sendable () async -> any AsyncSequence<[DashboardDeviceDescription], Never> & Sendable,
            reorderFavorite: @escaping @Sendable (String, String) async -> Void,
            refreshAll: @escaping @Sendable () async -> Void
        ) {
            self.observeFavoritesSource = observeFavorites
            self.reorderFavoriteAction = reorderFavorite
            self.refreshAllAction = refreshAll
        }

        func observeFavorites(
            onUpdate: @escaping @Sendable ([DashboardDeviceDescription]) async -> Void
        ) async {
            let stream = await observeFavoritesSource()
            for await favoriteDevices in stream {
                guard !Task.isCancelled else { return }
                await onUpdate(favoriteDevices)
            }
        }

        func refreshAll() async {
            await refreshAllAction()
        }

        func reorderFavorite(sourceId: String, targetId: String) async {
            await reorderFavoriteAction(sourceId, targetId)
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
