struct DashboardDeviceCardStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (FavoriteType) -> DashboardDeviceCardStore

    init(make: @escaping @MainActor @Sendable (FavoriteType) -> DashboardDeviceCardStore) {
        self.makeStore = make
    }

    @MainActor
    func make(favoriteType: FavoriteType) -> DashboardDeviceCardStore {
        makeStore(favoriteType)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let favoritesRepository = dependencyBag.localStorageDatasources.favoritesRepository

        return Self { favoriteType in
            DashboardDeviceCardStore(
                favoriteType: favoriteType,
                toggleFavorite: .init(
                    toggleFavorite: { favoriteType in
                        try? await favoritesRepository.toggleFavorite(favoriteType)
                    }
                ),
            )
        }
    }
}
