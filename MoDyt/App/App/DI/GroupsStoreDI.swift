import DeltaDoreClient

struct GroupsStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable () -> GroupsStore

    init(make: @escaping @MainActor @Sendable () -> GroupsStore) {
        self.makeStore = make
    }

    @MainActor
    func make() -> GroupsStore {
        makeStore()
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let groupRepository = dependencyBag.localStorageDatasources.groupRepository
        let favoritesRepository = dependencyBag.localStorageDatasources.favoritesRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self {
            GroupsStore(
                observeGroups: .init(
                    observeGroups: { await groupRepository.observeAll() }
                ),
                toggleFavorite: .init(
                    toggleFavorite: { groupID in
                        try? await favoritesRepository.toggleGroupFavorite(groupID)
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
