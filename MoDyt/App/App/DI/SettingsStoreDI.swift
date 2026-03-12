import DeltaDoreClient

struct SettingsStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable () -> SettingsStore

    init(make: @escaping @MainActor @Sendable () -> SettingsStore) {
        self.makeStore = make
    }

    @MainActor
    func make() -> SettingsStore {
        makeStore()
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let gatewayClient = dependencyBag.gatewayClient
        let messageRouter = dependencyBag.localStorageDatasources.tydomMessageRepositoryRouter

        return Self {
            SettingsStore(
                requestDisconnect: .init(
                    requestDisconnect: {
                        await gatewayClient.disconnectCurrentConnection()
                        await gatewayClient.clearStoredData()
                        await messageRouter.clearRepositories()
                    }
                )
            )
        }
    }
}
