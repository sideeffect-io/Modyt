import Foundation

public extension TydomGatewayCredentialFetcher.Dependencies {
    static func live(store: TydomGatewayCredentialStore) -> TydomGatewayCredentialFetcher.Dependencies {
        TydomGatewayCredentialFetcher.Dependencies(
            makeSession: {
                URLSession(configuration: .default)
            },
            fetchPassword: { email, password, mac, session in
                try await TydomCloudPasswordProvider.fetchGatewayPassword(
                    email: email,
                    password: password,
                    mac: mac,
                    session: session
                )
            },
            now: { Date() },
            save: { gatewayId, credentials in
                try await store.save(gatewayId, credentials)
            }
        )
    }
}
