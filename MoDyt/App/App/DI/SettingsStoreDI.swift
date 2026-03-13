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
                refreshConnectionRoute: .init(
                    readConnectionRoute: {
                        guard let mode = await gatewayClient.currentConnectionMode() else {
                            return .unavailable
                        }

                        switch mode {
                        case .local(let host):
                            return .local(host: host)
                        case .remote(let host):
                            return .remote(host: host)
                        }
                    }
                ),
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
