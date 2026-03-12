import Foundation
import Observation

struct DashboardFavoritesObservation: Sendable, Equatable {
    let devices: [Device]
    let groups: [Group]
    let scenes: [Scene]
}

struct DashboardState: Sendable, Equatable {
    var favorites: [FavoriteItem]

    static let initial = DashboardState(favorites: [])
}

enum DashboardEvent: Sendable {
    case onAppear
    case favoritesObserved(DashboardFavoritesObservation)
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
        static func reduce(
            _ state: DashboardState,
            _ event: DashboardEvent
        ) -> Transition<DashboardState, DashboardEffect> {
            var state = state

            switch event {
            case .onAppear:
                return .init(state: state, effects: [.startObservingFavorites])

            case .favoritesObserved(let observation):
                state.favorites = FavoriteItemsProjector.items(
                    devices: observation.devices,
                    groups: observation.groups,
                    scenes: observation.scenes
                )
                return .init(state: state)

            case .refreshRequested:
                return .init(state: state, effects: [.refreshAll])

            case .reorderFavorite(let source, let target):
                return .init(state: state, effects: [.reorderFavorite(source, target)])
            }
        }
    }

    private(set) var state: DashboardState = .initial

    private let observeFavorites: ObserveDashboardFavoritesEffectExecutor
    private let reorderFavorite: ReorderDashboardFavoriteEffectExecutor
    private let refreshAll: RefreshDashboardEffectExecutor
    private var favoritesTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        observeFavorites: ObserveDashboardFavoritesEffectExecutor,
        reorderFavorite: ReorderDashboardFavoriteEffectExecutor,
        refreshAll: RefreshDashboardEffectExecutor
    ) {
        self.observeFavorites = observeFavorites
        self.reorderFavorite = reorderFavorite
        self.refreshAll = refreshAll
    }

    func send(_ event: DashboardEvent) {
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
        favoritesTask?.cancel()
    }

    private func handle(_ effects: [DashboardEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: DashboardEffect) {
        switch effect {
        case .startObservingFavorites:
            guard favoritesTask == nil else { return }
            replaceTask(
                &favoritesTask,
                with: makeTrackedStreamTask(
                    operation: { [observeFavorites] in
                        await observeFavorites()
                    },
                    onEvent: { [weak self] event in
                        self?.send(event)
                    },
                    onFinish: { [weak self] in
                        self?.favoritesTask = nil
                    }
                )
            )

        case .refreshAll:
            launchFireAndForgetTask { [refreshAll] in
                await refreshAll()
            }

        case .reorderFavorite(let source, let target):
            launchFireAndForgetTask { [reorderFavorite] in
                await reorderFavorite(
                    source: source,
                    target: target
                )
            }
        }
    }
}
