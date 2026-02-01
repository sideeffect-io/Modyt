import Foundation
import DeltaDoreClient
import Persistence

enum DatabaseChange: Sendable, Equatable {
    case devicesUpdated
    case favoritesUpdated
    case layoutUpdated
}

actor DatabaseStore {
    private let database: SQLiteDatabase
    private let deviceDAO: DAO<DeviceRecord>
    private let stateDAO: DAO<DeviceStateRecord>
    private let favoritesDAO: DAO<FavoriteRecord>
    private let layoutDAO: DAO<DashboardLayoutRecord>

    private let changeStream: AsyncStream<DatabaseChange>
    private let changeContinuation: AsyncStream<DatabaseChange>.Continuation

    init(database: SQLiteDatabase) async throws {
        self.database = database
        try await Self.createTables(database: database)

        self.deviceDAO = DAO.make(
            database: database,
            schema: TableSchema<DeviceRecord>.codable(
                table: "devices",
                primaryKey: "id"
            )
        )
        self.stateDAO = DAO.make(
            database: database,
            schema: TableSchema<DeviceStateRecord>.codable(
                table: "device_state",
                primaryKey: "deviceKey"
            )
        )
        self.favoritesDAO = DAO.make(
            database: database,
            schema: TableSchema<FavoriteRecord>.codable(
                table: "favorites",
                primaryKey: "deviceKey"
            )
        )
        self.layoutDAO = DAO.make(
            database: database,
            schema: TableSchema<DashboardLayoutRecord>.codable(
                table: "dashboard_layout",
                primaryKey: "deviceKey"
            )
        )

        let stream = AsyncStream<DatabaseChange>.makeStream()
        self.changeStream = stream.stream
        self.changeContinuation = stream.continuation
    }

    static func live() async throws -> DatabaseStore {
        let url = try databaseURL()
        let db = try await SQLiteDatabase(path: url.path)
        return try await DatabaseStore(database: db)
    }

    func changes() async -> AsyncStream<DatabaseChange> {
        changeStream
    }

    func upsert(devices: [DeviceRecord]) async throws {
        guard !devices.isEmpty else { return }
        try await database.withTransaction { db in
            for device in devices {
                let values = try TableSchema<DeviceRecord>.codable(table: "devices", primaryKey: "id").encode(device)
                try await upsert(database: db, table: "devices", primaryKey: "id", values: values)
            }
        }
        changeContinuation.yield(.devicesUpdated)
    }

    func upsert(states: [DeviceStateRecord]) async throws {
        guard !states.isEmpty else { return }
        try await database.withTransaction { db in
            for state in states {
                let values = try TableSchema<DeviceStateRecord>.codable(table: "device_state", primaryKey: "deviceKey").encode(state)
                try await upsert(database: db, table: "device_state", primaryKey: "deviceKey", values: values)
            }
        }
        changeContinuation.yield(.devicesUpdated)
    }

    func listDeviceSnapshots() async throws -> [DeviceSnapshot] {
        let devices = try await deviceDAO.list()
        let states = try await stateDAO.list()
        let favorites = try await favoritesDAO.list()

        let stateMap = Dictionary(uniqueKeysWithValues: states.map { ($0.deviceKey, $0) })
        let favoriteSet = Set(favorites.map { $0.deviceKey })

        return devices.map { device in
            DeviceSnapshot(
                device: device,
                state: stateMap[device.id],
                isFavorite: favoriteSet.contains(device.id)
            )
        }
    }

    func listFavorites() async throws -> [FavoriteRecord] {
        try await favoritesDAO.list().sorted { $0.rank < $1.rank }
    }

    func listLayout() async throws -> [DashboardLayoutRecord] {
        try await layoutDAO.list()
    }

    func stateData(for deviceKey: String) async throws -> [String: JSONValue]? {
        let record = try await stateDAO.read(SQLiteValue.text(deviceKey))
        return record?.data
    }

    func setFavorite(deviceKey: String, isFavorite: Bool) async throws {
        if isFavorite {
            let nextRank = try await nextFavoriteRank()
            let record = FavoriteRecord(deviceKey: deviceKey, rank: nextRank)
            let values = try TableSchema<FavoriteRecord>.codable(table: "favorites", primaryKey: "deviceKey").encode(record)
            try await upsert(database: database, table: "favorites", primaryKey: "deviceKey", values: values)
        } else {
            try await favoritesDAO.delete(SQLiteValue.text(deviceKey))
        }
        changeContinuation.yield(.favoritesUpdated)
    }

    func setLayout(_ layout: [DashboardLayoutRecord]) async throws {
        try await database.withTransaction { db in
            for placement in layout {
                let values = try TableSchema<DashboardLayoutRecord>.codable(
                    table: "dashboard_layout",
                    primaryKey: "deviceKey"
                ).encode(placement)
                try await upsert(database: db, table: "dashboard_layout", primaryKey: "deviceKey", values: values)
            }
        }
        changeContinuation.yield(.layoutUpdated)
    }

    private func nextFavoriteRank() async throws -> Int {
        let rows = try await favoritesDAO.queryRows(
            "SELECT MAX(rank) as maxRank FROM favorites",
            []
        )
        guard let row = rows.first, case let .integer(value)? = row.value("maxRank") else {
            return 0
        }
        return Int(value) + 1
    }

    private static func databaseURL() throws -> URL {
        let manager = FileManager.default
        let folder = try manager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let appFolder = folder.appendingPathComponent("MoDyt", isDirectory: true)
        if manager.fileExists(atPath: appFolder.path) == false {
            try manager.createDirectory(at: appFolder, withIntermediateDirectories: true)
        }
        return appFolder.appendingPathComponent("modty.sqlite")
    }

    private static func createTables(database: SQLiteDatabase) async throws {
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS devices (
                id TEXT PRIMARY KEY,
                deviceId INTEGER NOT NULL,
                endpointId INTEGER NOT NULL,
                uniqueId TEXT NOT NULL,
                name TEXT NOT NULL,
                usage TEXT NOT NULL,
                kind TEXT NOT NULL,
                data BLOB NOT NULL,
                metadata BLOB NULL,
                updatedAt REAL NOT NULL
            )
            """
        )
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS device_state (
                deviceKey TEXT PRIMARY KEY,
                data BLOB NOT NULL,
                updatedAt REAL NOT NULL
            )
            """
        )
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS favorites (
                deviceKey TEXT PRIMARY KEY,
                rank INTEGER NOT NULL
            )
            """
        )
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS dashboard_layout (
                deviceKey TEXT PRIMARY KEY,
                row INTEGER NOT NULL,
                column INTEGER NOT NULL,
                span INTEGER NOT NULL
            )
            """
        )
        try await database.execute(
            """
            CREATE TABLE IF NOT EXISTS app_settings (
                key TEXT PRIMARY KEY,
                value TEXT NOT NULL
            )
            """
        )
    }

    private func upsert(
        database: SQLiteDatabase,
        table: String,
        primaryKey: String,
        values: [String: SQLiteValue]
    ) async throws {
        let columns = values.keys.sorted()
        let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
        let assignments = columns
            .filter { $0 != primaryKey }
            .map { "\"\($0)\" = excluded.\"\($0)\"" }
            .joined(separator: ", ")
        let columnList = columns.map { "\"\($0)\"" }.joined(separator: ", ")
        let sql: String
        if assignments.isEmpty {
            sql = "INSERT OR IGNORE INTO \"\(table)\" (\(columnList)) VALUES (\(placeholders))"
        } else {
            sql = "INSERT INTO \"\(table)\" (\(columnList)) VALUES (\(placeholders)) ON CONFLICT(\"\(primaryKey)\") DO UPDATE SET \(assignments)"
        }
        let bindings = columns.map { values[$0] ?? .null }
        try await database.execute(sql, bindings)
    }
}
