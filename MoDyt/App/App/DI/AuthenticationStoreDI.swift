import SwiftUI
import DeltaDoreClient

enum AuthenticationStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> AuthenticationStore.Dependencies {
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            inspectFlow: {
                await gatewayClient.inspectConnectionFlow()
            },
            connectStored: {
                _ = try await gatewayClient.connectWithStoredCredentials(options: .init())
            },
            listSites: { email, password in
                let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                return try await gatewayClient.listSites(cloudCredentials: credentials)
            },
            connectNew: { email, password, siteIndex in
                let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                _ = try await gatewayClient.connectWithNewCredentials(
                    options: .init(mode: .auto(cloudCredentials: credentials)),
                    selectSiteIndex: { _ in siteIndex }
                )
            }
        )
    }
}

extension EnvironmentValues {
    @Entry var authenticationStoreDependencies: AuthenticationStore.Dependencies =
        AuthenticationStoreDependencyFactory.make()
}
