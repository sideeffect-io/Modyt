import DeltaDoreClient

struct ScenesStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable () -> ScenesStore

    init(make: @escaping @MainActor @Sendable () -> ScenesStore) {
        self.makeStore = make
    }

    @MainActor
    func make() -> ScenesStore {
        makeStore()
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let sceneRepository = dependencyBag.localStorageDatasources.sceneRepository
        let favoritesRepository = dependencyBag.localStorageDatasources.favoritesRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self {
            ScenesStore(
                observeScenes: .init(
                    observeScenes: { await sceneRepository.observeAll() }
                ),
                toggleFavorite: .init(
                    toggleFavorite: { sceneID in
                        try? await favoritesRepository.toggleSceneFavorite(sceneID)
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
