import Foundation

public struct DAO<Entity: Codable & Sendable>: Sendable {
    public let create: @Sendable (Entity) throws -> Entity
    public let read: @Sendable (SQLiteValue) throws -> Entity?
    public let update: @Sendable (Entity) throws -> Entity
    public let delete: @Sendable (SQLiteValue) throws -> Void
    public let deleteAll: @Sendable () throws -> Void
    public let list: @Sendable () throws -> [Entity]
    public let query: @Sendable (String, [SQLiteValue]) throws -> [Entity]
    public let queryRows: @Sendable (String, [SQLiteValue]) throws -> [Row]

    public init(
        create: @escaping @Sendable (Entity) throws -> Entity,
        read: @escaping @Sendable (SQLiteValue) throws -> Entity?,
        update: @escaping @Sendable (Entity) throws -> Entity,
        delete: @escaping @Sendable (SQLiteValue) throws -> Void,
        deleteAll: @escaping @Sendable () throws -> Void,
        list: @escaping @Sendable () throws -> [Entity],
        query: @escaping @Sendable (String, [SQLiteValue]) throws -> [Entity],
        queryRows: @escaping @Sendable (String, [SQLiteValue]) throws -> [Row]
    ) {
        self.create = create
        self.read = read
        self.update = update
        self.delete = delete
        self.deleteAll = deleteAll
        self.list = list
        self.query = query
        self.queryRows = queryRows
    }
}

extension DAO {
    public static func make(
        database: SQLiteDatabase,
        schema: TableSchema<Entity>
    ) -> DAO<Entity> {
        DAO(
            create: { entity in
                let values = try schema.encode(entity)
                let columns = values.keys.sorted()
                let sql = insertSQL(table: schema.table, columns: columns)
                let bindings = columns.map { values[$0] ?? .null }
                try database.execute(sql, bindings)
                return entity
            },
            read: { id in
                let sql = selectByIDSQL(table: schema.table, primaryKey: schema.primaryKey)
                let rows = try database.query(sql, [id])
                guard let row = rows.first else { return nil }
                return try schema.decode(row)
            },
            update: { entity in
                let values = try schema.encode(entity)
                guard let idValue = values[schema.primaryKey], !idValue.isNull else {
                    throw SQLiteError.missingPrimaryKey(schema.primaryKey)
                }
                let columns = values.keys.filter { $0 != schema.primaryKey }.sorted()
                guard !columns.isEmpty else {
                    throw SQLiteError.unsupportedEncoding("No columns to update")
                }
                let sql = updateSQL(table: schema.table, primaryKey: schema.primaryKey, columns: columns)
                let bindings = columns.map { values[$0] ?? .null } + [idValue]
                try database.execute(sql, bindings)
                return entity
            },
            delete: { id in
                let sql = deleteSQL(table: schema.table, primaryKey: schema.primaryKey)
                try database.execute(sql, [id])
            },
            deleteAll: {
                let sql = deleteAllSQL(table: schema.table)
                try database.execute(sql)
            },
            list: {
                let sql = selectAllSQL(table: schema.table)
                let rows = try database.query(sql)
                return try rows.map(schema.decode)
            },
            query: { sql, bindings in
                let rows = try database.query(sql, bindings)
                return try rows.map(schema.decode)
            },
            queryRows: { sql, bindings in
                try database.query(sql, bindings)
            }
        )
    }
}

private func insertSQL(table: String, columns: [String]) -> String {
    let columnList = columns.map(quoted).joined(separator: ", ")
    let placeholders = Array(repeating: "?", count: columns.count).joined(separator: ", ")
    return "INSERT INTO \(quoted(table)) (\(columnList)) VALUES (\(placeholders))"
}

private func selectByIDSQL(table: String, primaryKey: String) -> String {
    "SELECT * FROM \(quoted(table)) WHERE \(quoted(primaryKey)) = ? LIMIT 1"
}

private func updateSQL(table: String, primaryKey: String, columns: [String]) -> String {
    let assignments = columns.map { "\(quoted($0)) = ?" }.joined(separator: ", ")
    return "UPDATE \(quoted(table)) SET \(assignments) WHERE \(quoted(primaryKey)) = ?"
}

private func deleteSQL(table: String, primaryKey: String) -> String {
    "DELETE FROM \(quoted(table)) WHERE \(quoted(primaryKey)) = ?"
}

private func deleteAllSQL(table: String) -> String {
    "DELETE FROM \(quoted(table))"
}

private func selectAllSQL(table: String) -> String {
    "SELECT * FROM \(quoted(table))"
}

private func quoted(_ name: String) -> String {
    "\"\(name)\""
}
