import Foundation
import Persistence

enum SQLiteDomainMergeDecision<Item: DomainType>: Sendable {
    case upsert(Item)
    case delete(id: String)
}

actor SQLiteDomainRepository<Item: DomainType, Upsert: DomainUpsert> {
    enum RepositoryError: Error {
        case notReady
    }

    struct Configuration: Sendable {
        let databasePath: String
        let tableName: String
        let createTableSQL: String
        let createDashboardOrderIndexSQL: String
        let resolveUpsert: @Sendable (Item?, Upsert, Date) -> SQLiteDomainMergeDecision<Item>
    }

    private let configuration: Configuration
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void

    private var dao: DAO<Item>?
    private var snapshot: [Item]?
    private var continuations: [UUID: AsyncStream<[Item]>.Continuation] = [:]

    init(
        configuration: Configuration,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.now = now
        self.log = log
    }

    func startIfNeeded() throws {
        guard dao == nil else {
            return
        }

        let database = try SQLiteDatabase(path: configuration.databasePath)
        try database.execute(configuration.createTableSQL)
        try database.execute(configuration.createDashboardOrderIndexSQL)

        let schema = TableSchema<Item>.codable(
            table: configuration.tableName,
            primaryKey: "id"
        )

        self.dao = DAO.make(database: database, schema: schema)
    }

    func observeAll() -> some AsyncSequence<[Item], Never> & Sendable {
        do {
            let snapshot = try currentSnapshot()
            return stream(initialSnapshot: snapshot).removeDuplicates()
        } catch {
            log("\(type(of: self)) sqlite observeAll failed: \(error)")
            return AsyncStream<[Item]>.single([]).removeDuplicates()
        }
    }

    func observeByID(_ id: String) -> some AsyncSequence<Item?, Never> & Sendable {
        observeByIDs([id]).map { $0.first }.removeDuplicates()
    }

    func observeByIDs(_ ids: [String]) -> some AsyncSequence<[Item], Never> & Sendable {
        observeAll().map { Self.project($0, by: ids) }.removeDuplicates()
    }
    
    func observeFavorites() -> some AsyncSequence<[Item], Never> & Sendable {
        observeAll().map { Self.filterFavorites($0) }.removeDuplicates()
    }

    func listAll() throws -> [Item] {
        try currentSnapshot()
    }

    func listByIDs(_ ids: [String]) throws -> [Item] {
        let snapshot = try currentSnapshot()
        return Self.project(snapshot, by: ids)
    }

    func get(_ id: String) throws -> Item? {
        let snapshot = try currentSnapshot()
        return snapshot.first(where: { $0.id == id })
    }

    func upsert(_ values: [Upsert]) throws {
        guard values.isEmpty == false else {
            return
        }

        let dao = try requireDAO()
        var didChange = false

        for value in values {
            let upsertID = value.id
            let existing = try dao.read(.text(upsertID))
            let decision = configuration.resolveUpsert(existing, value, now())

            switch decision {
            case .delete(let id):
                let existingToDelete: Item?
                if id == upsertID {
                    existingToDelete = existing
                } else {
                    existingToDelete = try dao.read(.text(id))
                }

                guard existingToDelete != nil else {
                    continue
                }

                try dao.delete(.text(id))
                didChange = true
            case .upsert(let merged):
                let existingForMerged: Item?
                if merged.id == upsertID {
                    existingForMerged = existing
                } else {
                    existingForMerged = try dao.read(.text(merged.id))
                }

                if let existingForMerged {
                    guard existingForMerged != merged else {
                        continue
                    }

                    _ = try dao.update(merged)
                    didChange = true
                } else {
                    _ = try dao.create(merged)
                    didChange = true
                }
            }
        }

        if didChange {
            try refreshSnapshotAndNotify()
        }
    }

    func deleteByIDs(_ ids: [String]) async throws {
        let orderedIDs = ids.uniquePreservingOrder()
        guard orderedIDs.isEmpty == false else {
            return
        }

        let dao = try requireDAO()
        var didChange = false

        for id in orderedIDs {
            guard try dao.read(.text(id)) != nil else {
                continue
            }

            try dao.delete(.text(id))
            didChange = true
        }

        if didChange {
            try refreshSnapshotAndNotify()
        }
    }

    func setFavorite(_ id: String, _ isFavorite: Bool) throws {
        let dao = try requireDAO()
        let snapshot = try currentSnapshot()

        guard var item = snapshot.first(where: { $0.id == id }) else {
            return
        }

        let alreadyFavorite = item.isFavorite
        if alreadyFavorite == isFavorite {
            if isFavorite, item.dashboardOrder == nil {
                item.dashboardOrder = nextFavoriteDashboardOrder(from: snapshot)
            } else {
                return
            }
        } else if isFavorite {
            item.isFavorite = true
            item.dashboardOrder = nextFavoriteDashboardOrder(from: snapshot)
        } else {
            item.isFavorite = false
            item.dashboardOrder = nil
        }

        item.updatedAt = now()
        _ = try dao.update(item)
        try refreshSnapshotAndNotify()
    }

    func applyDashboardOrders(_ orders: [String: Int]) async throws {
        guard orders.isEmpty == false else {
            return
        }

        let dao = try requireDAO()
        let snapshot = try currentSnapshot()
        let snapshotByID = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })

        var didChange = false

        for (id, order) in orders {
            guard var existing = snapshotByID[id] else {
                continue
            }

            guard existing.isFavorite else {
                continue
            }

            guard existing.dashboardOrder != order else {
                continue
            }

            existing.dashboardOrder = order
            existing.updatedAt = now()
            _ = try dao.update(existing)
            didChange = true
        }

        if didChange {
            try refreshSnapshotAndNotify()
        }
    }

    private func requireDAO() throws -> DAO<Item> {
        try startIfNeeded()

        guard let dao else {
            throw RepositoryError.notReady
        }

        return dao
    }

    private func currentSnapshot() throws -> [Item] {
        if let snapshot {
            return snapshot
        }

        let loaded = try fetchSnapshot()
        snapshot = loaded
        return loaded
    }

    private func fetchSnapshot() throws -> [Item] {
        let dao = try requireDAO()
        let values = try dao.list()
        return values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func refreshSnapshotAndNotify() throws {
        let refreshed = try fetchSnapshot()
        publish(refreshed)
    }

    private func stream(initialSnapshot: [Item]) -> AsyncStream<[Item]> {
        let observerID = UUID()
        let (stream, continuation) = AsyncStream<[Item]>.makeStream()

        continuations[observerID] = continuation

        if let snapshot {
            continuation.yield(snapshot)
        } else {
            snapshot = initialSnapshot
            continuation.yield(initialSnapshot)
        }

        continuation.onTermination = { [repository = self] _ in
            Task {
                await repository.removeObserver(observerID)
            }
        }

        return stream
    }

    private func publish(_ snapshot: [Item]) {
        if self.snapshot == snapshot {
            return
        }

        self.snapshot = snapshot
        for continuation in continuations.values {
            continuation.yield(snapshot)
        }
    }

    private func removeObserver(_ observerID: UUID) {
        continuations[observerID] = nil
    }

    private func nextFavoriteDashboardOrder(from snapshot: [Item]) -> Int {
        let maxOrder = snapshot
            .filter(\.isFavorite)
            .compactMap(\.dashboardOrder)
            .max() ?? -1

        return maxOrder + 1
    }

    private static func project(_ items: [Item], by ids: [String]) -> [Item] {
        guard ids.isEmpty == false else {
            return []
        }

        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }
    
    private static func filterFavorites(_ items: [Item]) -> [Item] {
        items.filter(\.isFavorite)
    }
}
