import DeltaDoreClient

struct DashboardStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable () -> DashboardStore

    init(make: @escaping @MainActor @Sendable () -> DashboardStore) {
        self.makeStore = make
    }

    @MainActor
    func make() -> DashboardStore {
        makeStore()
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let favoritesRepository = dependencyBag.localStorageDatasources.favoritesRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self {
            DashboardStore(
                observeFavorites: .init(
                    observeFavorites: {
                        let favoriteSources = await favoritesRepository.observeSourceSnapshot()

                        return favoriteSources
                            .map { sources in
                                DashboardFavoritesObservation(
                                    devices: sources.devices,
                                    groups: sources.groups,
                                    scenes: sources.scenes
                                )
                            }
                            .removeDuplicates()
                    }
                ),
                reorderFavorite: .init(
                    reorderFavorite: { source, target in
                        try? await favoritesRepository.reorder(source, target)
                    }
                ),
                refreshAll: .init(
                    refreshAll: {
                        try? await gatewayClient.send(text: TydomCommand.refreshAll().request)
                    }
                )
            )
        }
    }
}
