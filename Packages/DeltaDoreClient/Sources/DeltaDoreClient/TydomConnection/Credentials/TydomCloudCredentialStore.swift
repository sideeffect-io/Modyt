import Foundation

public struct TydomCloudCredentialStore: Sendable {
    public var load: @Sendable () async throws -> TydomConnection.CloudCredentials?
    public var save: @Sendable (_ credentials: TydomConnection.CloudCredentials) async throws -> Void
    public var deleteAll: @Sendable () async throws -> Void

    public static func inMemory(
        initial: TydomConnection.CloudCredentials? = nil
    ) -> TydomCloudCredentialStore {
        let actorStore = InMemoryStore(storage: initial)
        return TydomCloudCredentialStore(
            load: {
                await actorStore.load()
            },
            save: { credentials in
                await actorStore.save(credentials)
            },
            deleteAll: {
                await actorStore.deleteAll()
            }
        )
    }
}

private actor InMemoryStore {
    private var storage: TydomConnection.CloudCredentials?

    init(storage: TydomConnection.CloudCredentials?) {
        self.storage = storage
    }

    func load() -> TydomConnection.CloudCredentials? {
        storage
    }

    func save(_ credentials: TydomConnection.CloudCredentials) {
        storage = credentials
    }

    func deleteAll() {
        storage = nil
    }
}
