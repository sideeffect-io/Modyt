import Foundation
import Persistence

struct DeviceUpsert: DomainUpsert, Equatable {
    let id: String
    let endpointId: Int
    let name: String
    let usage: String
    let kind: String
    let data: [String: JSONValue]
    let metadata: [String: JSONValue]?
}

typealias DeviceRepository = DomainRepository<Device, DeviceUpsert>

extension DomainRepository where Item == Device, Upsert == DeviceUpsert {
    static func makeDeviceRepository(
        createDAO: @escaping DeviceRepository.DAOFactory,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> Self {
        Self(
            configuration: .init(
                resolveUpsert: { existing, upsert, timestamp in
                        .upsert(makeDevice(existing: existing, upsert: upsert, timestamp: timestamp))
                    }
            ),
            createDAO: createDAO,
            now: now,
            log: log
        )
    }

    static func makeDeviceRepository(
        databasePath: String,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> Self {
        makeDeviceRepository(
            createDAO: {
                let database = try SQLiteDatabase(path: databasePath)
                try database.execute(createTableSQL)
                try database.execute(createDashboardOrderIndexSQL)

                let schema = TableSchema<Device>.codable(
                    table: tableName,
                    primaryKey: "id"
                )

                return DAO.make(database: database, schema: schema)
            },
            now: now,
            log: log
        )
    }
    
    func observeGroupedByType() -> some AsyncSequence<[RepositoryDeviceTypeSection], Never> & Sendable {
        observeAll().map { devices in
            let grouped = Dictionary(grouping: devices, by: \.resolvedUsage)
            return Usage.allCases.compactMap { usage in
                guard let values = grouped[usage] else { return nil }
                let sorted = values.sorted(by: { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
                return RepositoryDeviceTypeSection(usage: usage, items: sorted)
            }
        }
    }
    
    private static func makeDevice(
        existing: Device?,
        upsert: DeviceUpsert,
        timestamp: Date
    ) -> Device {
        Device(
            id: upsert.id,
            endpointId: upsert.endpointId,
            name: upsert.name,
            usage: upsert.usage,
            kind: upsert.kind,
            data: existing?.data.mergedDictionary(incoming: upsert.data) ?? [:],
            metadata: existing?.metadata.mergedDictionary(incoming: upsert.metadata),
            isFavorite: existing?.isFavorite ?? false,
            dashboardOrder: existing?.dashboardOrder,
            updatedAt: timestamp
        )
    }
    
    private static let tableName = "devices"
    
    private static let createTableSQL = """
    CREATE TABLE IF NOT EXISTS \(tableName) (
        id TEXT PRIMARY KEY,
        endpointId INTEGER NOT NULL,
        name TEXT NOT NULL,
        usage TEXT NOT NULL,
        kind TEXT NOT NULL,
        data TEXT NOT NULL,
        metadata TEXT,
        isFavorite INTEGER NOT NULL,
        dashboardOrder INTEGER,
        updatedAt REAL NOT NULL
    );
    """
    
    private static let createDashboardOrderIndexSQL = """
    CREATE INDEX IF NOT EXISTS devices_favorites_order_idx
    ON \(tableName) (isFavorite, dashboardOrder);
    """
}
