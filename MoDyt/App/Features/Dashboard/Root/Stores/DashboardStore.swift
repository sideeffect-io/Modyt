import Foundation
import Observation
import DeltaDoreClient

struct DashboardState: Sendable, Equatable {
    var favorites: [FavoriteItem]

    static let initial = DashboardState(favorites: [])
}

enum DashboardEvent: Sendable {
    case onAppear
    case favoritesUpdated([FavoriteItem])
    case refreshRequested
    case reorderFavorite(FavoriteType, FavoriteType)
}

enum DashboardEffect: Sendable, Equatable {
    case startObservingFavorites
    case refreshAll
    case reorderFavorite(FavoriteType, FavoriteType)
}

@Observable
@MainActor
final class DashboardStore: StartableStore {
    struct StateMachine {
        var state: DashboardState = .initial

        mutating func reduce(_ event: DashboardEvent) -> [DashboardEffect] {
            switch event {
            case .onAppear:
                return [.startObservingFavorites]

            case .favoritesUpdated(let favorites):
                state.favorites = favorites
                return []

            case .refreshRequested:
                return [.refreshAll]

            case .reorderFavorite(let source, let target):
                return [.reorderFavorite(source, target)]
            }
        }
    }

    struct Dependencies {
        let observeFavorites: @Sendable () async -> any AsyncSequence<[FavoriteItem], Never> & Sendable
        let reorderFavorite: @Sendable (FavoriteType, FavoriteType) async -> Void
        let refreshAll: @Sendable () async -> Void
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: DashboardState {
        stateMachine.state
    }

    private let favoritesTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    init(dependencies: Dependencies) {
        self.worker = Worker(
            observeFavorites: dependencies.observeFavorites,
            reorderFavorite: dependencies.reorderFavorite,
            refreshAll: dependencies.refreshAll
        )
    }

    func send(_ event: DashboardEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    deinit {
        favoritesTask.cancel()
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
            let taskHandle = favoritesTask
            favoritesTask.task = Task { [weak self, worker, weak taskHandle] in
                defer {
                    Task { @MainActor [weak taskHandle] in
                        taskHandle?.task = nil
                    }
                }
                await worker.observeFavorites { [weak self] favorites in
                    await self?.send(.favoritesUpdated(favorites))
                }
            }

        case .refreshAll:
            Task { [worker] in
                await worker.refreshAll()
            }

        case .reorderFavorite(let source, let target):
            Task { [worker] in
                await worker.reorderFavorite(source: source, target: target)
            }
        }
    }

    private actor Worker {
        private let observeFavoritesSource: @Sendable () async -> any AsyncSequence<[FavoriteItem], Never> & Sendable
        private let reorderFavoriteAction: @Sendable (FavoriteType, FavoriteType) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeFavorites: @escaping @Sendable () async -> any AsyncSequence<[FavoriteItem], Never> & Sendable,
            reorderFavorite: @escaping @Sendable (FavoriteType, FavoriteType) async -> Void,
            refreshAll: @escaping @Sendable () async -> Void
        ) {
            self.observeFavoritesSource = observeFavorites
            self.reorderFavoriteAction = reorderFavorite
            self.refreshAllAction = refreshAll
        }

        func observeFavorites(
            onUpdate: @escaping @Sendable ([FavoriteItem]) async -> Void
        ) async {
            let stream = await observeFavoritesSource()
            for await favorites in stream {
                guard !Task.isCancelled else { return }
                await onUpdate(favorites)
            }
        }

        func refreshAll() async {
            await refreshAllAction()
        }

        func reorderFavorite(source: FavoriteType, target: FavoriteType) async {
            await reorderFavoriteAction(source, target)
        }
    }
}
