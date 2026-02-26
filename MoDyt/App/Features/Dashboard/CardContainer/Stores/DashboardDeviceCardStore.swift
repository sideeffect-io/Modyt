import Observation

enum DashboardDeviceCardEvent: Sendable {
    case favoriteTapped
}

@Observable
@MainActor
final class DashboardDeviceCardStore {
    struct Dependencies {
        let toggleFavorite: @Sendable (FavoriteType) async -> Void
    }

    private let favoriteType: FavoriteType
    private let worker: Worker

    init(favoriteType: FavoriteType, dependencies: Dependencies) {
        self.favoriteType = favoriteType
        self.worker = Worker(toggleFavorite: dependencies.toggleFavorite)
    }

    func send(_ event: DashboardDeviceCardEvent) {
        switch event {
        case .favoriteTapped:
            Task { [worker, favoriteType] in
                await worker.toggleFavorite(favoriteType)
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
