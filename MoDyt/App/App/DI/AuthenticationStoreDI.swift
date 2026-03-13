import DeltaDoreClient

struct AuthenticationStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (@escaping @MainActor (AuthenticationDelegateEvent) -> Void) -> AuthenticationStore

    init(
        make: @escaping @MainActor @Sendable (@escaping @MainActor (AuthenticationDelegateEvent) -> Void) -> AuthenticationStore
    ) {
        self.makeStore = make
    }

    @MainActor
    func make(
        onDelegateEvent: @escaping @MainActor (AuthenticationDelegateEvent) -> Void = { _ in }
    ) -> AuthenticationStore {
        makeStore(onDelegateEvent)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let gatewayClient = dependencyBag.gatewayClient

        return Self { onDelegateEvent in
            AuthenticationStore(
                inspectFlow: .init(
                    inspectFlow: {
                        switch await gatewayClient.inspectConnectionFlow() {
                        case .connectWithStoredCredentials:
                            return .connectWithStoredCredentials
                        case .connectWithNewCredentials:
                            return .connectWithNewCredentials
                        }
                    }
                ),
                connectStored: .init(
                    connectStored: {
                        _ = try await gatewayClient.renewStoredConnectionIfNeeded(
                            preferLocal: true,
                            livenessTimeout: 2.0
                        )
                    }
                ),
                listSites: .init(
                    listSites: { email, password in
                        let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                        return try await gatewayClient
                            .listSites(cloudCredentials: credentials)
                            .map { site in
                                AuthenticationSite(
                                    id: site.id,
                                    name: site.name,
                                    gatewayCount: site.gateways.count
                                )
                            }
                    }
                ),
                connectNew: .init(
                    connectNew: { email, password, siteIndex in
                        let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                        _ = try await gatewayClient.connectWithNewCredentials(
                            options: .init(mode: .auto(cloudCredentials: credentials)),
                            selectSiteIndex: { _ in siteIndex }
                        )
                    }
                ),
                onDelegateEvent: onDelegateEvent
            )
        }
    }
}
