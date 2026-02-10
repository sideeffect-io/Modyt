import Foundation
import DeltaDoreClient
import Persistence

actor DeviceRepository {
    enum RepositoryError: Error {
        case notReady
    }

    private let databasePath: String
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private var database: SQLiteDatabase?
    private var dao: DAO<DeviceRecord>?
    private var observers: [UUID: AsyncStream<[DeviceRecord]>.Continuation] = [:]

    init(
        databasePath: String,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.databasePath = databasePath
        self.now = now
        self.log = log
    }

    func startIfNeeded() async throws {
        if database != nil { return }
        let db = try await SQLiteDatabase(path: databasePath)
        try await db.execute(Self.createDevicesTableSQL)
        let schema = TableSchema<DeviceRecord>.codable(table: "devices", primaryKey: "uniqueId")
        let deviceDAO = DAO.make(database: db, schema: schema)
        database = db
        dao = deviceDAO
    }

    func observeDevices() -> AsyncStream<[DeviceRecord]> {
        let observerId = UUID()
        let (stream, continuation) = AsyncStream<[DeviceRecord]>.makeStream()

        addObserver(id: observerId, continuation: continuation)

        let snapshotTask = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }

            do {
                try await self.startIfNeeded()
                let snapshot = try await self.listDevices()
                log("Devices snapshot loaded count=\(snapshot.count)")
                continuation.yield(snapshot)
            } catch {
                log("Devices snapshot load failed error=\(error)")
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

    func observeFavorites() -> some AsyncSequence<[DeviceRecord], Never> & Sendable {
        observeDevices().map { snapshot in
            snapshot
                .filter(\.isFavorite)
                .sorted { lhs, rhs in
                    let lhsOrder = lhs.dashboardOrder ?? lhs.favoriteOrder ?? Int.max
                    let rhsOrder = rhs.dashboardOrder ?? rhs.favoriteOrder ?? Int.max
                    return lhsOrder < rhsOrder
                }
        }
        .removeDuplicates(by: Self.areFavoriteSnapshotsEquivalent)
    }

    func observeFavoriteDescriptions() -> some AsyncSequence<[DashboardDeviceDescription], Never> & Sendable {
        observeDevices().map { snapshot in
            snapshot
                .filter(\.isFavorite)
                .sorted { lhs, rhs in
                    let lhsOrder = lhs.dashboardOrder ?? lhs.favoriteOrder ?? Int.max
                    let rhsOrder = rhs.dashboardOrder ?? rhs.favoriteOrder ?? Int.max
                    return lhsOrder < rhsOrder
                }
                .map { device in
                    DashboardDeviceDescription(
                        uniqueId: device.uniqueId,
                        name: device.name,
                        usage: device.usage
                    )
                }
        }
        .removeDuplicates()
    }

    func observeDevice(uniqueId: String) -> some AsyncSequence<DeviceRecord?, Never> & Sendable {
        observeDevices().map { snapshot in
            snapshot.first(where: { $0.uniqueId == uniqueId })
        }
        .removeDuplicates(by: Self.areObservedDevicesEquivalent)
    }

    func device(uniqueId: String) async -> DeviceRecord? {
        guard let deviceDAO = try? await requireDAO() else { return nil }
        return try? await deviceDAO.read(.text(uniqueId))
    }

    func listDevices() async throws -> [DeviceRecord] {
        let deviceDAO = try await requireDAO()
        let devices = try await deviceDAO.list()
        return devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    func upsertDevices(_ devices: [TydomDevice]) async {
        guard let deviceDAO = try? await requireDAO() else { return }
        log("Upsert devices count=\(devices.count)")
        for device in devices {
            let existing = try? await deviceDAO.read(.text(device.uniqueId))
            let merged = merge(existing: existing, incoming: device, now: now())
            if existing == nil {
                _ = try? await deviceDAO.create(merged)
            } else {
                _ = try? await deviceDAO.update(merged)
            }
        }
        await notifyObservers()
    }

    func applyOptimisticUpdate(uniqueId: String, key: String, value: JSONValue) async {
        await applyOptimisticUpdates(uniqueId: uniqueId, changes: [key: value])
    }

    func applyOptimisticUpdates(uniqueId: String, changes: [String: JSONValue]) async {
        guard !changes.isEmpty else { return }
        guard let deviceDAO = try? await requireDAO() else { return }
        guard var existing = try? await deviceDAO.read(.text(uniqueId)) else { return }
        var data = existing.data
        for (key, value) in changes {
            data[key] = value
        }
        guard data != existing.data else { return }
        existing.data = data
        existing.updatedAt = now()
        _ = try? await deviceDAO.update(existing)
        await notifyObservers()
    }

    func toggleFavorite(uniqueId: String) async {
        guard let deviceDAO = try? await requireDAO() else { return }
        guard var existing = try? await deviceDAO.read(.text(uniqueId)) else { return }

        if existing.isFavorite {
            existing.isFavorite = false
            existing.favoriteOrder = nil
            existing.dashboardOrder = nil
        } else {
            let devices = (try? await deviceDAO.list()) ?? []
            let maxOrder = devices
                .filter { $0.isFavorite }
                .compactMap { $0.dashboardOrder ?? $0.favoriteOrder }
                .max() ?? -1
            existing.isFavorite = true
            existing.favoriteOrder = maxOrder + 1
            existing.dashboardOrder = maxOrder + 1
        }

        existing.updatedAt = now()
        _ = try? await deviceDAO.update(existing)
        await notifyObservers()
    }

    func reorderDashboard(from sourceId: String, to targetId: String) async {
        guard let deviceDAO = try? await requireDAO() else { return }
        let devices = (try? await deviceDAO.list()) ?? []
        var favorites = devices
            .filter { $0.isFavorite }
            .sorted { dashboardOrder(for: $0) < dashboardOrder(for: $1) }

        guard let fromIndex = favorites.firstIndex(where: { $0.uniqueId == sourceId }),
              let toIndex = favorites.firstIndex(where: { $0.uniqueId == targetId }),
              fromIndex != toIndex else {
            return
        }

        let moved = favorites.remove(at: fromIndex)
        favorites.insert(moved, at: toIndex)

        for (index, device) in favorites.enumerated() {
            var updated = device
            let newOrder = index
            if updated.dashboardOrder != newOrder || updated.favoriteOrder != newOrder {
                updated.dashboardOrder = newOrder
                updated.favoriteOrder = newOrder
                updated.updatedAt = now()
                _ = try? await deviceDAO.update(updated)
            }
        }

        await notifyObservers()
    }

    func applyMessage(_ message: TydomMessage) async {
        switch message {
        case .devices(let devices, _):
            log("Apply devices message count=\(devices.count)")
            await upsertDevices(devices)
        default:
            break
        }
    }

    private func dashboardOrder(for device: DeviceRecord) -> Int {
        if let order = device.dashboardOrder { return order }
        if let order = device.favoriteOrder { return order }
        return Int.max
    }

    private func addObserver(
        id: UUID,
        continuation: AsyncStream<[DeviceRecord]>.Continuation
    ) {
        observers[id] = continuation
    }

    private func removeObserver(id: UUID) {
        observers[id] = nil
    }

    private func notifyObservers() async {
        guard let deviceDAO = try? await requireDAO() else { return }
        let devices = (try? await deviceDAO.list()) ?? []
        let sorted = devices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        log("Notify observers count=\(sorted.count)")
        for continuation in observers.values {
            continuation.yield(sorted)
        }
    }

    private func requireDAO() async throws -> DAO<DeviceRecord> {
        try await startIfNeeded()
        guard let dao else { throw RepositoryError.notReady }
        return dao
    }

    private static func areFavoriteSnapshotsEquivalent(
        _ lhs: [DeviceRecord],
        _ rhs: [DeviceRecord]
    ) async -> Bool {
        guard lhs.count == rhs.count else { return false }
        return zip(lhs, rhs).allSatisfy { left, right in
            left.isEquivalentForFavorites(to: right)
        }
    }

    private static func areObservedDevicesEquivalent(
        _ lhs: DeviceRecord?,
        _ rhs: DeviceRecord?
    ) async -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            true
        case let (.some(left), .some(right)):
            left.isEquivalentForObservation(to: right)
        default:
            false
        }
    }

    private static let createDevicesTableSQL = """
    CREATE TABLE IF NOT EXISTS devices (
        uniqueId TEXT PRIMARY KEY,
        deviceId INTEGER NOT NULL,
        endpointId INTEGER NOT NULL,
        name TEXT NOT NULL,
        usage TEXT NOT NULL,
        kind TEXT NOT NULL,
        data TEXT NOT NULL,
        metadata TEXT,
        isFavorite INTEGER NOT NULL,
        favoriteOrder INTEGER,
        dashboardOrder INTEGER,
        updatedAt REAL NOT NULL
    );
    """
}

private func merge(
    existing: DeviceRecord?,
    incoming: TydomDevice,
    now: Date
) -> DeviceRecord {
    let mergedData = mergeDictionaries(existing?.data, incoming.data)
    let mergedMetadata = mergeDictionaries(existing?.metadata, incoming.metadata)
    return DeviceRecord(
        uniqueId: incoming.uniqueId,
        deviceId: incoming.id,
        endpointId: incoming.endpointId,
        name: incoming.name,
        usage: incoming.usage,
        kind: DeviceGroup.from(usage: incoming.usage).rawValue,
        data: mergedData,
        metadata: mergedMetadata,
        isFavorite: existing?.isFavorite ?? false,
        favoriteOrder: existing?.favoriteOrder,
        dashboardOrder: existing?.dashboardOrder,
        updatedAt: now
    )
}

private func mergeDictionaries(
    _ existing: [String: JSONValue]?,
    _ incoming: [String: JSONValue]?
) -> [String: JSONValue] {
    var merged = existing ?? [:]
    if let incoming {
        for (key, value) in incoming {
            merged[key] = value
        }
    }
    return merged
}
