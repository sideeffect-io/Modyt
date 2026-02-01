import Foundation

public struct TydomGatewayMacStore: Sendable {
    public var load: @Sendable () async throws -> String?
    public var save: @Sendable (_ mac: String) async throws -> Void
    public var delete: @Sendable () async throws -> Void

    public static func inMemory(
        initial: String? = nil
    ) -> TydomGatewayMacStore {
        let actorStore = InMemoryStore(storage: initial)
        return TydomGatewayMacStore(
            load: {
                await actorStore.load()
            },
            save: { mac in
                await actorStore.save(mac)
            },
            delete: {
                await actorStore.delete()
            }
        )
    }
}

private actor InMemoryStore {
    private var storage: String?

    init(storage: String?) {
        self.storage = storage
    }

    func load() -> String? {
        storage
    }

    func save(_ mac: String) {
        storage = TydomMac.normalize(mac)
    }

    func delete() {
        storage = nil
    }
}
