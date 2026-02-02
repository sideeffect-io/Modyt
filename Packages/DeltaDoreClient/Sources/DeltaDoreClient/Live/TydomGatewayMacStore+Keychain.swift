import Foundation

#if canImport(Security)
import Security

public extension TydomGatewayMacStore {
    static func liveKeychain(
        service: String = "io.sideeffect.deltadoreclient.gateway-mac"
    ) -> TydomGatewayMacStore {
        let store = KeychainStore<Payload>(service: service)
        let account = "gateway-mac"
        return TydomGatewayMacStore(
            load: {
                guard let payload = try await store.load(account: account) else {
                    return nil
                }
                return TydomMac.normalize(payload.mac)
            },
            save: { mac in
                let payload = Payload(mac: TydomMac.normalize(mac))
                try await store.save(account: account, value: payload)
            },
            delete: {
                try await store.delete(account: account)
            }
        )
    }
}

private struct Payload: Codable {
    let mac: String
}
#endif
