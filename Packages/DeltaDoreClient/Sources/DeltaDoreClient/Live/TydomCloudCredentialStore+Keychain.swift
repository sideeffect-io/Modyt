import Foundation

#if canImport(Security)
import Security

public extension TydomCloudCredentialStore {
    static func liveKeychain(
        service: String = "io.sideeffect.deltadoreclient.cloud-credentials"
    ) -> TydomCloudCredentialStore {
        let store = KeychainStore<Payload>(service: service)
        let account = "cloud-credentials"
        return TydomCloudCredentialStore(
            load: {
                guard let payload = try await store.load(account: account) else {
                    return nil
                }
                return TydomConnection.CloudCredentials(
                    email: payload.email,
                    password: payload.password
                )
            },
            save: { credentials in
                let payload = Payload(email: credentials.email, password: credentials.password)
                try await store.save(account: account, value: payload)
            },
            deleteAll: {
                try await store.delete(account: account)
            }
        )
    }
}

private struct Payload: Codable {
    let email: String
    let password: String
}
#endif
