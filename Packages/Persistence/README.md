# Persistence

Persistence is a small Swift package that provides a SQLite-backed DAO (Data Access Object) layer for storing `Codable` entities. It exposes a minimal, async/await API and lets you model tables with a lightweight schema description.

## How it works

The module is built around a few core types:

- `SQLiteDatabase`: an `actor` that owns a SQLite connection. It prepares statements, binds values, executes SQL, and returns rows. It is fully async and safe to use across tasks.
- `TableSchema<Entity>`: describes how a Swift entity maps to a SQLite table (table name, primary key, encoder/decoder).
- `DAO<Entity>`: a set of CRUD + query operations generated from a `SQLiteDatabase` and a `TableSchema`.
- `SQLiteEncoder` / `SQLiteDecoder`: convert between `Codable` entities and a flat row representation.
- `Row` and `SQLiteValue`: represent a SQLite row and its column values.

### Encoding and decoding rules

`SQLiteEncoder` and `SQLiteDecoder` work at a *single-row* level:

- Only keyed encoding/decoding is supported (no nested keyed/unkeyed containers).
- Primitive Swift types map to SQLite types:
  - `Bool` -> `.integer(0/1)`
  - `Int`, `UInt`, etc. -> `.integer`
  - `Float`, `Double` -> `.real`
  - `String` -> `.text`
  - `Data` -> `.blob`
  - `Date` -> seconds since 1970 (`.real`)
  - `URL` -> `.text` (absolute string)
- For any other `Codable` type, the encoder stores JSON (as UTF-8 text when possible, otherwise as a blob). The decoder expects JSON text/blob for those columns.

## Usage

### 1) Define a model

```swift
struct User: Codable, Sendable {
    let id: Int64
    let name: String
    let createdAt: Date
}
```

### 2) Create a table and schema

```swift
let database = try await SQLiteDatabase(path: databaseURL.path)
try await database.execute(
    """
    CREATE TABLE IF NOT EXISTS users (
        id INTEGER PRIMARY KEY,
        name TEXT NOT NULL,
        createdAt REAL NOT NULL
    )
    """
)

let schema = TableSchema<User>.codable(
    table: "users",
    primaryKey: "id"
)
```

### 3) Build a DAO and use it

```swift
let users = DAO.make(database: database, schema: schema)

let created = try await users.create(
    User(id: 1, name: "Ada", createdAt: Date())
)

let fetched = try await users.read(.integer(1))
let all = try await users.list()

let updated = try await users.update(
    User(id: 1, name: "Ada Lovelace", createdAt: created.createdAt)
)

try await users.delete(.integer(1))
```

### 4) Custom queries

```swift
let results = try await users.query(
    "SELECT * FROM users WHERE name LIKE ?",
    [.text("Ada%")]
)

let rows = try await users.queryRows(
    "SELECT COUNT(*) AS total FROM users",
    []
)
```

### 5) Transactions

```swift
try await database.withTransaction { db in
    let users = DAO.make(database: db, schema: schema)
    _ = try await users.create(User(id: 2, name: "Grace", createdAt: Date()))
    _ = try await users.create(User(id: 3, name: "Katherine", createdAt: Date()))
}
```

## Extending

### Custom column mapping

If your table column names don't match your Swift property names, or you need to transform values, build a custom `TableSchema`:

```swift
struct Session: Codable, Sendable {
    let identifier: UUID
    let expiresAt: Date
}

let schema = TableSchema<Session>(
    table: "sessions",
    primaryKey: "id",
    encode: { session in
        [
            "id": .text(session.identifier.uuidString),
            "expires_at": .real(session.expiresAt.timeIntervalSince1970)
        ]
    },
    decode: { row in
        guard
            case let .text(idText)? = row.value("id"),
            case let .real(seconds)? = row.value("expires_at"),
            let id = UUID(uuidString: idText)
        else {
            throw SQLiteError.decodingFailed(message: "Invalid session row")
        }
        return Session(identifier: id, expiresAt: Date(timeIntervalSince1970: seconds))
    }
)
```

### Custom JSON behavior

Provide a custom `SQLiteCodingOptions` if you need specific `JSONEncoder`/`JSONDecoder` behavior (date strategies, key strategies, etc.).

```swift
let options = SQLiteCodingOptions(
    jsonEncoder: {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    },
    jsonDecoder: {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
)

let schema = TableSchema<MyType>.codable(
    table: "my_table",
    primaryKey: "id",
    options: options
)
```

### Alternative storage or testing

`DAO` is just a set of async closures. You can build your own DAO implementation for in-memory tests or alternative storage engines without SQLite:

```swift
let memoryDAO = DAO<User>(
    create: { $0 },
    read: { _ in nil },
    update: { $0 },
    delete: { _ in },
    list: { [] },
    query: { _, _ in [] },
    queryRows: { _, _ in [] }
)
```

## Notes and constraints

- The DAO `update` method requires a non-null primary key value in the encoded row.
- Only flat (single-row) encoding is supported. Use custom schemas or JSON columns for nested structures.
- Prefer parameter bindings (`?`) to avoid SQL injection when running custom queries.
- This package does not include migrations; table creation and evolution are up to the host app.
