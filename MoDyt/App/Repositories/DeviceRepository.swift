import Foundation
import Persistence

struct DeviceUpsert: DomainUpsert, Equatable {
    let id: DeviceIdentifier
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
                    },
                idValue: sqliteValue
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
                    primaryKey: "id",
                    options: sqliteCodingOptions
                )

                return DAO.make(database: database, schema: schema)
            },
            now: now,
            log: log
        )
    }
    
    func observeByDeviceID(_ deviceId: Int) -> some AsyncSequence<[Device], Never> & Sendable {
        observeAll()
            .map { devices in
                devices.filter { $0.deviceId == deviceId }
            }
            .removeDuplicates()
    }

    func setShutterTargetPosition(
        deviceId: DeviceIdentifier,
        target: Int?
    ) throws {
        try setShutterTargetPosition(
            deviceIds: [deviceId],
            target: target
        )
    }

    func setShutterTargetPosition(
        deviceIds: [DeviceIdentifier],
        target: Int?
    ) throws {
        try mutateByIDs(deviceIds) { device in
            guard device.resolvedUsage == .shutter else {
                return
            }
            device.shutterTargetPosition = target
        }
    }
    
    private static func makeDevice(
        existing: Device?,
        upsert: DeviceUpsert,
        timestamp: Date
    ) -> Device {
        Device(
            id: upsert.id,
            deviceId: upsert.id.deviceId,
            endpointId: upsert.id.endpointId,
            name: upsert.name,
            usage: upsert.usage,
            kind: upsert.kind,
            data: existing?.data.mergedDictionary(incoming: upsert.data) ?? upsert.data,
            metadata: existing?.metadata.mergedDictionary(incoming: upsert.metadata) ?? upsert.metadata,
            isFavorite: existing?.isFavorite ?? false,
            dashboardOrder: existing?.dashboardOrder,
            shutterTargetPosition: existing?.shutterTargetPosition,
            updatedAt: timestamp
        )
    }
    
    private static let tableName = "devices"
    
    private static let createTableSQL = """
    CREATE TABLE IF NOT EXISTS \(tableName) (
        id TEXT PRIMARY KEY,
        deviceId INTEGER NOT NULL,
        endpointId INTEGER NOT NULL,
        name TEXT NOT NULL,
        usage TEXT NOT NULL,
        kind TEXT NOT NULL,
        data TEXT NOT NULL,
        metadata TEXT,
        isFavorite INTEGER NOT NULL,
        dashboardOrder INTEGER,
        shutterTargetPosition INTEGER,
        updatedAt REAL NOT NULL
    );
    """
    
    private static let createDashboardOrderIndexSQL = """
    CREATE INDEX IF NOT EXISTS devices_favorites_order_idx
    ON \(tableName) (isFavorite, dashboardOrder);
    """

    private static let sqliteCodingOptions = SQLiteCodingOptions(
        jsonEncoder: {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            return encoder
        },
        jsonDecoder: {
            JSONDecoder()
        }
    )

    private static func sqliteValue(for id: DeviceIdentifier) -> SQLiteValue {
        let encoder = sqliteCodingOptions.jsonEncoder()
        if let data = try? encoder.encode(id),
           let text = String(data: data, encoding: .utf8) {
            return .text(text)
        }

        // Fallback keeps lookups stable even if encoding fails unexpectedly.
        return .text("{\"deviceId\":\(id.deviceId),\"endpointId\":\(id.endpointId)}")
    }
}
