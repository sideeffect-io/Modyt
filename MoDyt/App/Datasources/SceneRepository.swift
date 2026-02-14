import Foundation
import DeltaDoreClient
import Persistence

actor SceneRepository {
    enum RepositoryError: Error {
        case notReady
    }

    private let databasePath: String
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private let trackMessage: @Sendable (TydomMessage) async -> Void
    private var database: SQLiteDatabase?
    private var dao: DAO<SceneRecord>?
    private var observers: [UUID: AsyncStream<[SceneRecord]>.Continuation] = [:]

    init(
        databasePath: String,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in },
        trackMessage: @escaping @Sendable (TydomMessage) async -> Void = { _ in }
    ) {
        self.databasePath = databasePath
        self.now = now
        self.log = log
        self.trackMessage = trackMessage
    }

    func startIfNeeded() async throws {
        if database != nil { return }
        let db = try await SQLiteDatabase(path: databasePath)
        try await db.execute(Self.createScenesTableSQL)
        let schema = TableSchema<SceneRecord>.codable(table: "scenes", primaryKey: "uniqueId")
        let sceneDAO = DAO.make(database: db, schema: schema)
        database = db
        dao = sceneDAO
    }

    func observeScenes() -> AsyncStream<[SceneRecord]> {
        let observerId = UUID()
        let (stream, continuation) = AsyncStream<[SceneRecord]>.makeStream()

        addObserver(id: observerId, continuation: continuation)

        let snapshotTask = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }

            do {
                try await self.startIfNeeded()
                let snapshot = try await self.listScenes()
                log("Scenes snapshot loaded count=\(snapshot.count)")
                continuation.yield(snapshot)
            } catch {
                log("Scenes snapshot load failed error=\(error)")
                await self.removeObserver(id: observerId)
                continuation.finish()
            }
        }

        continuation.onTermination = { [weak self] _ in
            snapshotTask.cancel()
            Task { await self?.removeObserver(id: observerId) }
        }

        return stream
    }

    func observeFavoriteDescriptions() -> some AsyncSequence<[DashboardDeviceDescription], Never> & Sendable {
        observeScenes().map { snapshot in
            snapshot
                .filter(\.isFavorite)
                .sorted { lhs, rhs in
                    let lhsOrder = lhs.dashboardOrder ?? lhs.favoriteOrder ?? Int.max
                    let rhsOrder = rhs.dashboardOrder ?? rhs.favoriteOrder ?? Int.max
                    return lhsOrder < rhsOrder
                }
                .map(Self.makeDashboardDescription(from:))
        }
        .removeDuplicates()
    }

    func favoriteDescriptionsSnapshot() async -> [DashboardDeviceDescription] {
        guard let sceneDAO = try? await requireDAO() else { return [] }
        let scenes = (try? await sceneDAO.list()) ?? []
        return scenes
            .filter(\.isFavorite)
            .sorted { lhs, rhs in
                let lhsOrder = lhs.dashboardOrder ?? lhs.favoriteOrder ?? Int.max
                let rhsOrder = rhs.dashboardOrder ?? rhs.favoriteOrder ?? Int.max
                return lhsOrder < rhsOrder
            }
            .map(Self.makeDashboardDescription(from:))
    }

    func listScenes() async throws -> [SceneRecord] {
        let sceneDAO = try await requireDAO()
        let scenes = try await sceneDAO.list()
        return scenes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func upsertScenes(_ scenes: [TydomScenario]) async {
        guard let sceneDAO = try? await requireDAO() else { return }
        let internalUniqueIds = Set(
            scenes
                .filter(\.isGatewayInternal)
                .map { SceneRecord.uniqueId(for: $0.id) }
        )
        let visibleScenes = scenes.filter { !$0.isGatewayInternal }

        log("Upsert scenes count=\(scenes.count) visible=\(visibleScenes.count) internal=\(internalUniqueIds.count)")

        for uniqueId in internalUniqueIds {
            _ = try? await sceneDAO.delete(.text(uniqueId))
        }

        for scene in visibleScenes {
            let uniqueId = SceneRecord.uniqueId(for: scene.id)
            let existing = try? await sceneDAO.read(.text(uniqueId))
            let merged = merge(existing: existing, incoming: scene, now: now())
            if existing == nil {
                _ = try? await sceneDAO.create(merged)
            } else {
                _ = try? await sceneDAO.update(merged)
            }
        }

        await notifyObservers()
    }

    func toggleFavorite(uniqueId: String) async {
        guard let sceneDAO = try? await requireDAO() else { return }
        guard var existing = try? await sceneDAO.read(.text(uniqueId)) else { return }

        if existing.isFavorite {
            existing.isFavorite = false
            existing.favoriteOrder = nil
            existing.dashboardOrder = nil
        } else {
            let scenes = (try? await sceneDAO.list()) ?? []
            let maxOrder = scenes
                .filter { $0.isFavorite }
                .compactMap { $0.dashboardOrder ?? $0.favoriteOrder }
                .max() ?? -1
            existing.isFavorite = true
            existing.favoriteOrder = maxOrder + 1
            existing.dashboardOrder = maxOrder + 1
        }

        existing.updatedAt = now()
        _ = try? await sceneDAO.update(existing)
        await notifyObservers()
    }

    func reorderDashboard(from sourceId: String, to targetId: String) async {
        guard let sceneDAO = try? await requireDAO() else { return }
        let scenes = (try? await sceneDAO.list()) ?? []
        var favorites = scenes
            .filter { $0.isFavorite }
            .sorted { dashboardOrder(for: $0) < dashboardOrder(for: $1) }

        guard let fromIndex = favorites.firstIndex(where: { $0.uniqueId == sourceId }),
              let toIndex = favorites.firstIndex(where: { $0.uniqueId == targetId }),
              fromIndex != toIndex else {
            return
        }

        let moved = favorites.remove(at: fromIndex)
        favorites.insert(moved, at: toIndex)

        for (index, scene) in favorites.enumerated() {
            var updated = scene
            let newOrder = index
            if updated.dashboardOrder != newOrder || updated.favoriteOrder != newOrder {
                updated.dashboardOrder = newOrder
                updated.favoriteOrder = newOrder
                updated.updatedAt = now()
                _ = try? await sceneDAO.update(updated)
            }
        }

        await notifyObservers()
    }

    func applyDashboardOrders(_ orders: [String: Int]) async {
        guard !orders.isEmpty else { return }
        guard let sceneDAO = try? await requireDAO() else { return }

        var didUpdate = false
        for (uniqueId, order) in orders {
            guard var existing = try? await sceneDAO.read(.text(uniqueId)) else { continue }
            guard existing.isFavorite else { continue }
            guard existing.dashboardOrder != order || existing.favoriteOrder != order else {
                continue
            }

            existing.dashboardOrder = order
            existing.favoriteOrder = order
            existing.updatedAt = now()
            _ = try? await sceneDAO.update(existing)
            didUpdate = true
        }

        if didUpdate {
            await notifyObservers()
        }
    }

    func applyMessage(_ message: TydomMessage) async {
        await trackMessage(message)

        switch message {
        case .scenarios(let scenarios, _):
            log("Apply scenarios message count=\(scenarios.count)")
            await upsertScenes(scenarios)
        default:
            break
        }
    }

    private func dashboardOrder(for scene: SceneRecord) -> Int {
        if let order = scene.dashboardOrder { return order }
        if let order = scene.favoriteOrder { return order }
        return Int.max
    }

    private func addObserver(
        id: UUID,
        continuation: AsyncStream<[SceneRecord]>.Continuation
    ) {
        observers[id] = continuation
    }

    private func removeObserver(id: UUID) {
        observers[id] = nil
    }

    private func notifyObservers() async {
        guard let sceneDAO = try? await requireDAO() else { return }
        let scenes = (try? await sceneDAO.list()) ?? []
        let sorted = scenes.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        log("Notify scene observers count=\(sorted.count)")
        for continuation in observers.values {
            continuation.yield(sorted)
        }
    }

    private func requireDAO() async throws -> DAO<SceneRecord> {
        try await startIfNeeded()
        guard let dao else { throw RepositoryError.notReady }
        return dao
    }

    private static func makeDashboardDescription(from scene: SceneRecord) -> DashboardDeviceDescription {
        DashboardDeviceDescription(
            uniqueId: scene.uniqueId,
            name: scene.name,
            usage: "scene",
            resolvedGroup: .other,
            dashboardOrder: scene.dashboardOrder ?? scene.favoriteOrder,
            source: .scene,
            sceneType: scene.type,
            scenePicto: scene.picto
        )
    }

    private static let createScenesTableSQL = """
    CREATE TABLE IF NOT EXISTS scenes (
        uniqueId TEXT PRIMARY KEY,
        sceneId INTEGER NOT NULL,
        name TEXT NOT NULL,
        type TEXT NOT NULL,
        picto TEXT NOT NULL,
        ruleId TEXT,
        payload TEXT NOT NULL,
        isFavorite INTEGER NOT NULL,
        favoriteOrder INTEGER,
        dashboardOrder INTEGER,
        updatedAt REAL NOT NULL
    );
    """
}

private func merge(
    existing: SceneRecord?,
    incoming: TydomScenario,
    now: Date
) -> SceneRecord {
    let uniqueId = SceneRecord.uniqueId(for: incoming.id)
    return SceneRecord(
        uniqueId: uniqueId,
        sceneId: incoming.id,
        name: incoming.name,
        type: incoming.type,
        picto: incoming.picto,
        ruleId: incoming.ruleId,
        payload: incoming.payload,
        isFavorite: existing?.isFavorite ?? false,
        favoriteOrder: existing?.favoriteOrder,
        dashboardOrder: existing?.dashboardOrder,
        updatedAt: now
    )
}

private extension TydomScenario {
    var isGatewayInternal: Bool {
        type.caseInsensitiveCompare("RE2020") == .orderedSame
    }
}
