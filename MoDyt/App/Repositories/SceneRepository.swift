import Foundation
import Persistence

struct SceneUpsert: DomainUpsert, Equatable {
    let id: String
    let name: String
    let type: String
    let picto: String
    let ruleId: String?
    let payload: [String: JSONValue]
    let isGatewayInternal: Bool
}

typealias SceneRepository = DomainRepository<Scene, SceneUpsert>

extension DomainRepository where Item == Scene, Upsert == SceneUpsert {
    static func makeSceneRepository(
        createDAO: @escaping SceneRepository.DAOFactory,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> Self {
        Self(
            configuration: .init(
                resolveUpsert: resolveUpsert
            ),
            createDAO: createDAO,
            now: now,
            log: log
        )
    }

    static func makeSceneRepository(
        databasePath: String,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> Self {
        makeSceneRepository(
            createDAO: {
                let database = try SQLiteDatabase(path: databasePath)
                try database.execute(createTableSQL)
                try database.execute(createDashboardOrderIndexSQL)

                let schema = TableSchema<Scene>.codable(
                    table: tableName,
                    primaryKey: "id"
                )

                return DAO.make(database: database, schema: schema)
            },
            now: now,
            log: log
        )
    }

    private static func resolveUpsert(
        existing: Scene?,
        upsert: SceneUpsert,
        timestamp: Date
    ) -> DomainMergeDecision<Scene> {
        if upsert.isGatewayInternal {
            return .delete(id: upsert.id)
        }

        return .upsert(
            Scene(
                id: upsert.id,
                name: upsert.name,
                type: upsert.type,
                picto: upsert.picto,
                ruleId: upsert.ruleId,
                payload: existing?.payload.mergedDictionary(incoming: upsert.payload) ?? [:],
                isFavorite: existing?.isFavorite ?? false,
                dashboardOrder: existing?.dashboardOrder,
                updatedAt: timestamp
            )
        )
    }

    private static let tableName = "scenes"

    private static let createTableSQL = """
    CREATE TABLE IF NOT EXISTS \(tableName) (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        picto TEXT NOT NULL,
        ruleId TEXT,
        payload TEXT NOT NULL,
        isFavorite INTEGER NOT NULL,
        dashboardOrder INTEGER,
        updatedAt REAL NOT NULL
    );
    """

    private static let createDashboardOrderIndexSQL = """
    CREATE INDEX IF NOT EXISTS scenes_favorites_order_idx
    ON \(tableName) (isFavorite, dashboardOrder);
    """
}
