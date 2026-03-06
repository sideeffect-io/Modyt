import Observation

enum DashboardDeviceCardEvent: Sendable {
    case favoriteTapped
}

struct DashboardDeviceCardState: Sendable, Equatable {
    static let initial = DashboardDeviceCardState()
}

enum DashboardDeviceCardEffect: Sendable, Equatable {
    case toggleFavorite(FavoriteType)
}

@Observable
@MainActor
final class DashboardDeviceCardStore: StartableStore {
    struct StateMachine {
        var state: DashboardDeviceCardState = .initial

        mutating func reduce(
            _ event: DashboardDeviceCardEvent,
            favoriteType: FavoriteType
        ) -> [DashboardDeviceCardEffect] {
            switch event {
            case .favoriteTapped:
                return [.toggleFavorite(favoriteType)]
            }
        }
    }

    struct Dependencies {
        let toggleFavorite: @Sendable (FavoriteType) async -> Void
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: DashboardDeviceCardState {
        stateMachine.state
    }

    private let favoriteType: FavoriteType
    private let worker: Worker

    init(
        dependencies: Dependencies,
        favoriteType: FavoriteType
    ) {
        self.favoriteType = favoriteType
        self.worker = Worker(toggleFavorite: dependencies.toggleFavorite)
    }

    func start() {}

    func send(_ event: DashboardDeviceCardEvent) {
        let effects = stateMachine.reduce(event, favoriteType: favoriteType)
        for effect in effects {
            switch effect {
            case .toggleFavorite(let favoriteType):
                Task { [worker] in
                    await worker.toggleFavorite(favoriteType)
                }
            }
        }
    }

    private actor Worker {
        private let toggleFavoriteAction: @Sendable (FavoriteType) async -> Void

        init(toggleFavorite: @escaping @Sendable (FavoriteType) async -> Void) {
            self.toggleFavoriteAction = toggleFavorite
        }

        func toggleFavorite(_ favoriteType: FavoriteType) async {
            await toggleFavoriteAction(favoriteType)
        }
    }
}
