import SwiftUI
import DeltaDoreClient

struct AuthenticationStoreFactory {
    let make: @MainActor (@escaping @MainActor () -> Void) -> AuthenticationStore

    static func live(dependencies: DependencyBag) -> AuthenticationStoreFactory {
        AuthenticationStoreFactory { onAuthenticated in
            AuthenticationStore(
                dependencies: .init(
                    inspectFlow: {
                        await dependencies.gatewayClient.inspectConnectionFlow()
                    },
                    connectStored: {
                        _ = try await dependencies.gatewayClient.connectWithStoredCredentials(options: .init())
                    },
                    listSites: { email, password in
                        let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                        return try await dependencies.gatewayClient.listSites(cloudCredentials: credentials)
                    },
                    connectNew: { email, password, siteIndex in
                        let credentials = TydomConnection.CloudCredentials(email: email, password: password)
                        _ = try await dependencies.gatewayClient.connectWithNewCredentials(
                            options: .init(mode: .auto(cloudCredentials: credentials)),
                            selectSiteIndex: { _ in siteIndex }
                        )
                    }
                ),
                onDelegateEvent: { delegateEvent in
                    if case .authenticated = delegateEvent {
                        onAuthenticated()
                    }
                }
            )
        }
    }
}

private struct AuthenticationStoreFactoryKey: EnvironmentKey {
    static var defaultValue: AuthenticationStoreFactory {
        AuthenticationStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var authenticationStoreFactory: AuthenticationStoreFactory {
        get { self[AuthenticationStoreFactoryKey.self] }
        set { self[AuthenticationStoreFactoryKey.self] = newValue }
    }
}
