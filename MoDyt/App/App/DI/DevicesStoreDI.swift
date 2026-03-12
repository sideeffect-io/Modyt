import DeltaDoreClient

struct DevicesStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable () -> DevicesStore

    init(make: @escaping @MainActor @Sendable () -> DevicesStore) {
        self.makeStore = make
    }

    @MainActor
    func make() -> DevicesStore {
        makeStore()
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let favoritesRepository = dependencyBag.localStorageDatasources.favoritesRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self {
            DevicesStore(
                observeDevices: .init(
                    observeDevices: { await deviceRepository.observeAll() }
                ),
                toggleFavorite: .init(
                    toggleFavorite: { deviceID in
                        try? await favoritesRepository.toggleDeviceFavorite(deviceID)
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
