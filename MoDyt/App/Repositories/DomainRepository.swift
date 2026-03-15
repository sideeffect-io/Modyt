import Foundation
import Persistence

enum DomainMergeDecision<Item: DomainType>: Sendable {
    case upsert(Item)
    case delete(id: Item.ID)
}

actor DomainRepository<Item: DomainType, Upsert: DomainUpsert> where Item.ID == Upsert.ID {
    enum RepositoryError: Error {
        case notReady
    }

    struct Configuration: Sendable {
        let resolveUpsert: @Sendable (Item?, Upsert, Date) -> DomainMergeDecision<Item>
        let idValue: @Sendable (Item.ID) -> SQLiteValue
    }

    typealias DAOFactory = @Sendable () throws -> DAO<Item>

    private let configuration: Configuration
    private let createDAO: DAOFactory
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void

    private var dao: DAO<Item>?
    private var snapshot: [Item]?
    private var continuations: [UUID: AsyncStream<[Item]>.Continuation] = [:]

    init(
        configuration: Configuration,
        createDAO: @escaping DAOFactory,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.createDAO = createDAO
        self.now = now
        self.log = log
    }

    func startIfNeeded() throws {
        guard dao == nil else {
            return
        }

        self.dao = try createDAO()
    }

    func observeAll() -> some AsyncSequence<[Item], Never> & Sendable {
        do {
            let snapshot = try currentSnapshot()
            return stream(initialSnapshot: snapshot).removeDuplicates()
        } catch {
            log("\(type(of: self)) observeAll failed: \(error)")
            return AsyncStream<[Item]> { continuation in
                continuation.finish()
            }
            .removeDuplicates()
        }
    }

    func observeByID(_ id: Item.ID) -> some AsyncSequence<Item?, Never> & Sendable {
        observeByIDs([id]).map { $0.first }.removeDuplicates()
    }

    func observeByIDs(_ ids: [Item.ID]) -> some AsyncSequence<[Item], Never> & Sendable {
        observeAll().map { Self.project($0, by: ids) }.removeDuplicates()
    }
    
    func listAll() throws -> [Item] {
        try currentSnapshot()
    }

    func listByIDs(_ ids: [Item.ID]) throws -> [Item] {
        let snapshot = try currentSnapshot()
        return Self.project(snapshot, by: ids)
    }

    func get(_ id: Item.ID) throws -> Item? {
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
            let existing = try dao.read(configuration.idValue(upsertID))
            let decision = configuration.resolveUpsert(existing, value, now())

            switch decision {
            case .delete(let id):
                let existingToDelete: Item?
                if id == upsertID {
                    existingToDelete = existing
                } else {
                    existingToDelete = try dao.read(configuration.idValue(id))
                }

                guard existingToDelete != nil else {
                    continue
                }

                try dao.delete(configuration.idValue(id))
                didChange = true
            case .upsert(let merged):
                let existingForMerged: Item?
                if merged.id == upsertID {
                    existingForMerged = existing
                } else {
                    existingForMerged = try dao.read(configuration.idValue(merged.id))
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

    func deleteByIDs(_ ids: [Item.ID]) async throws {
        let orderedIDs = ids.uniquePreservingOrder()
        guard orderedIDs.isEmpty == false else {
            return
        }

        let dao = try requireDAO()
        var didChange = false

        for id in orderedIDs {
            guard try dao.read(configuration.idValue(id)) != nil else {
                continue
            }

            try dao.delete(configuration.idValue(id))
            didChange = true
        }

        if didChange {
            try refreshSnapshotAndNotify()
        }
    }

    func deleteAll() async throws {
        let snapshot = try currentSnapshot()
        guard snapshot.isEmpty == false else {
            return
        }

        let dao = try requireDAO()
        try dao.deleteAll()
        try refreshSnapshotAndNotify()
    }

    func mutateByIDs(
        _ ids: [Item.ID],
        mutation: @Sendable (inout Item) -> Void
    ) throws {
        let orderedIDs = ids.uniquePreservingOrder()
        guard orderedIDs.isEmpty == false else {
            return
        }

        let dao = try requireDAO()
        let snapshot = try currentSnapshot()
        let snapshotByID = Dictionary(uniqueKeysWithValues: snapshot.map { ($0.id, $0) })

        var didChange = false

        for id in orderedIDs {
            guard var existing = snapshotByID[id] else {
                continue
            }

            let original = existing
            mutation(&existing)

            guard existing.id == original.id else {
                continue
            }

            guard existing != original else {
                continue
            }

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

    private static func project(_ items: [Item], by ids: [Item.ID]) -> [Item] {
        guard ids.isEmpty == false else {
            return []
        }

        let lookup = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
        return ids.compactMap { lookup[$0] }
    }
}
