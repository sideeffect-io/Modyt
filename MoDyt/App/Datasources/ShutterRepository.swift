import Foundation
import Persistence

actor ShutterRepository {
    enum RepositoryError: Error {
        case notReady
    }

    private struct TargetSnapshot: Sendable, Equatable {
        let positions: [Int]
        let revision: UInt64
    }

    private struct TargetRecord: Codable, Sendable, Equatable {
        let uniqueId: String
        var targetPosition: Int
        var updatedAt: Date?
    }

    private struct TargetObserver {
        let uniqueIds: [String]
        let watchedIdSet: Set<String>
        let continuation: AsyncStream<TargetSnapshot>.Continuation
    }

    private let databasePath: String
    private let deviceRepository: DeviceDatasource
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void

    private var database: SQLiteDatabase?
    private var dao: DAO<TargetRecord>?
    private var targetObservers: [UUID: TargetObserver] = [:]
    private var targetRevision: UInt64 = 0

    init(
        databasePath: String,
        deviceRepository: DeviceDatasource,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.databasePath = databasePath
        self.deviceRepository = deviceRepository
        self.now = now
        self.log = log
    }

    func startIfNeeded() async throws {
        if database != nil { return }

        let db = try await SQLiteDatabase(path: databasePath)
        try await db.execute(Self.createShutterTargetsTableSQL)
        if await Self.hasUpdatedAtColumn(database: db) == false {
            try? await db.execute(Self.addUpdatedAtColumnSQL)
        }
        let schema = TableSchema<TargetRecord>.codable(table: "shutter_targets", primaryKey: "uniqueId")
        let targetDAO = DAO.make(database: db, schema: schema)

        database = db
        dao = targetDAO
    }

    func observeShutterTargets(uniqueIds: [String]) -> AsyncStream<[Int]> {
        let snapshotStream = observeShutterTargetSnapshots(uniqueIds: uniqueIds)
        let (stream, continuation) = AsyncStream<[Int]>.makeStream()

        let forwardingTask = Task {
            for await snapshot in snapshotStream {
                continuation.yield(snapshot.positions)
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            forwardingTask.cancel()
        }

        return stream
    }

    private func observeShutterTargetSnapshots(uniqueIds: [String]) -> AsyncStream<TargetSnapshot> {
        let observerId = UUID()
        let orderedUniqueIds = Self.uniqueIds(from: uniqueIds)
        let (stream, continuation) = AsyncStream<TargetSnapshot>.makeStream()

        addTargetObserver(
            id: observerId,
            uniqueIds: orderedUniqueIds,
            continuation: continuation
        )

        let snapshotTask = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }

            do {
                try await self.startIfNeeded()
                let snapshot = try await self.targetPositions(for: orderedUniqueIds)
                let targetSnapshot = await self.makeTargetSnapshot(from: snapshot)
                continuation.yield(targetSnapshot)
            } catch {
                log("Shutter target snapshot load failed error=\(error)")
                await self.removeTargetObserver(id: observerId)
                continuation.finish()
            }
        }

        continuation.onTermination = { [weak self] _ in
            snapshotTask.cancel()
            Task { await self?.removeTargetObserver(id: observerId) }
        }

        return stream
    }

    func observeShuttersPositions(
        uniqueIds: [String]
    ) async -> AsyncStream<(actual: Int, target: Int)> {
        let orderedUniqueIds = Self.uniqueIds(from: uniqueIds)
        let positionsStream = await observeShutterPositions(uniqueIds: orderedUniqueIds)
            .map { [log] positions in
                let ids = orderedUniqueIds.joined(separator: ",")
                let values = positions.map(String.init).joined(separator: ",")
                log("Shutter actual stream ids=\(ids) values=\(values)")
                return positions
            }
        let targetsStream = observeShutterTargetSnapshots(uniqueIds: orderedUniqueIds)
            .map { [log] snapshot in
                let ids = orderedUniqueIds.joined(separator: ",")
                let values = snapshot.positions.map(String.init).joined(separator: ",")
                log("Shutter target stream ids=\(ids) revision=\(snapshot.revision) values=\(values)")
                return snapshot
            }

        let aggregatedStream = combineLatest(positionsStream, targetsStream)
            .map { [log] actualPositions, targetSnapshot in
                let targetPositions = targetSnapshot.positions
                let actualAverage = Self.averagePosition(for: actualPositions)
                let targetAverage = Self.averagePosition(for: targetPositions)
                let ids = orderedUniqueIds.joined(separator: ",")
                log(
                    "ShutterTrace repository aggregate ids=\(ids) actualRaw=\(actualPositions.map(String.init).joined(separator: ",")) targetRevision=\(targetSnapshot.revision) targetRaw=\(targetPositions.map(String.init).joined(separator: ",")) actualAvg=\(actualAverage) targetAvg=\(targetAverage)"
                )
                return (actual: actualAverage, target: targetAverage, targetRevision: targetSnapshot.revision)
            }

        let dedupedAggregatedStream = aggregatedStream.removeDuplicates(by: { lhs, rhs in
            lhs.actual == rhs.actual
                && lhs.target == rhs.target
                && lhs.targetRevision == rhs.targetRevision
        })

        let combinedStream = dedupedAggregatedStream
            .map { [log] values in
                let ids = orderedUniqueIds.joined(separator: ",")
                log(
                    "Shutter combined stream ids=\(ids) actual=\(values.actual) target=\(values.target)"
                )
                return (actual: values.actual, target: values.target)
            }

        let (stream, continuation) = AsyncStream<(actual: Int, target: Int)>.makeStream()

        let forwardingTask = Task {
            for await value in combinedStream {
                continuation.yield(value)
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            forwardingTask.cancel()
        }

        return stream
    }

    func setShutterTarget(uniqueId: String, targetPosition: Int) async {
        guard let targetDAO = try? await requireDAO() else { return }
        let clampedTarget = Self.clampPosition(targetPosition)
        let updatedAt = now()

        if var existing = try? await targetDAO.read(.text(uniqueId)) {
            if existing.targetPosition != clampedTarget {
                log(
                    "ShutterTrace repository target-write uniqueId=\(uniqueId) old=\(existing.targetPosition) new=\(clampedTarget)"
                )
                existing.targetPosition = clampedTarget
            } else {
                log(
                    "ShutterTrace repository target-reaffirm uniqueId=\(uniqueId) value=\(clampedTarget)"
                )
            }
            existing.updatedAt = updatedAt
            _ = try? await targetDAO.update(existing)
        } else {
            let record = TargetRecord(
                uniqueId: uniqueId,
                targetPosition: clampedTarget,
                updatedAt: updatedAt
            )
            log(
                "ShutterTrace repository target-create uniqueId=\(uniqueId) new=\(clampedTarget)"
            )
            _ = try? await targetDAO.create(record)
        }

        await notifyTargetObservers(for: [uniqueId])
    }

    func setShuttersTarget(uniqueIds: [String], targetPosition: Int) async {
        for uniqueId in uniqueIds {
            await setShutterTarget(uniqueId: uniqueId, targetPosition: targetPosition)
        }
    }

    private func observeShutterPositions(
        uniqueIds: [String]
    ) async -> some AsyncSequence<[Int], Never> & Sendable {
        let devicesStream = await deviceRepository.observeDevices()
        return devicesStream.map { [log] devices in
            let devicesById = Dictionary(uniqueKeysWithValues: devices.map { ($0.uniqueId, $0) })
            return uniqueIds.map { uniqueId in
                guard let device = devicesById[uniqueId],
                      let descriptor = Self.shutterDescriptor(for: device) else {
                    log("ShutterTrace repository actual-read uniqueId=\(uniqueId) descriptor=missing fallback=0")
                    return 0
                }
                let percent = Self.positionPercent(for: descriptor)
                log(
                    "ShutterTrace repository actual-read uniqueId=\(uniqueId) key=\(descriptor.key) value=\(Self.formatNumber(descriptor.value)) range=\(Self.formatNumber(descriptor.range.lowerBound))...\(Self.formatNumber(descriptor.range.upperBound)) percent=\(percent)"
                )
                return percent
            }
        }
    }

    private func addTargetObserver(
        id: UUID,
        uniqueIds: [String],
        continuation: AsyncStream<TargetSnapshot>.Continuation
    ) {
        targetObservers[id] = TargetObserver(
            uniqueIds: uniqueIds,
            watchedIdSet: Set(uniqueIds),
            continuation: continuation
        )
    }

    private func removeTargetObserver(id: UUID) {
        targetObservers[id] = nil
    }

    private func notifyTargetObservers(for changedUniqueIds: Set<String>? = nil) async {
        targetRevision &+= 1
        let revision = targetRevision

        for observer in targetObservers.values {
            if let changedUniqueIds, observer.watchedIdSet.isDisjoint(with: changedUniqueIds) {
                continue
            }

            guard let snapshot = try? await targetPositions(for: observer.uniqueIds) else {
                continue
            }
            log(
                "ShutterTrace repository target-notify ids=\(observer.uniqueIds.joined(separator: ",")) revision=\(revision) values=\(snapshot.map(String.init).joined(separator: ","))"
            )
            observer.continuation.yield(
                TargetSnapshot(
                    positions: snapshot,
                    revision: revision
                )
            )
        }
    }

    private func makeTargetSnapshot(from positions: [Int]) -> TargetSnapshot {
        TargetSnapshot(
            positions: positions,
            revision: targetRevision
        )
    }

    private func targetPositions(for uniqueIds: [String]) async throws -> [Int] {
        let targetDAO = try await requireDAO()

        var positions: [Int] = []
        positions.reserveCapacity(uniqueIds.count)

        for uniqueId in uniqueIds {
            if var existing = try await targetDAO.read(.text(uniqueId)) {
                if Self.isFresh(updatedAt: existing.updatedAt, now: now()) {
                    log(
                        "ShutterTrace repository target-read uniqueId=\(uniqueId) source=cache value=\(existing.targetPosition) fresh=true"
                    )
                    positions.append(Self.clampPosition(existing.targetPosition))
                    continue
                }

                let refreshedPosition = await initialShutterPosition(for: uniqueId)
                log(
                    "ShutterTrace repository target-read uniqueId=\(uniqueId) source=device-refresh old=\(existing.targetPosition) new=\(refreshedPosition)"
                )
                existing.targetPosition = refreshedPosition
                existing.updatedAt = now()
                _ = try? await targetDAO.update(existing)
                positions.append(refreshedPosition)
                continue
            }

            let initialPosition = await initialShutterPosition(for: uniqueId)
            log(
                "ShutterTrace repository target-read uniqueId=\(uniqueId) source=initial-device value=\(initialPosition)"
            )
            let record = TargetRecord(
                uniqueId: uniqueId,
                targetPosition: initialPosition,
                updatedAt: nil
            )
            _ = try? await targetDAO.create(record)
            positions.append(initialPosition)
        }

        return positions
    }

    private func initialShutterPosition(for uniqueId: String) async -> Int {
        guard let device = await deviceRepository.device(uniqueId: uniqueId),
              let descriptor = Self.shutterDescriptor(for: device) else {
            return 0
        }

        return Self.positionPercent(for: descriptor)
    }

    private func requireDAO() async throws -> DAO<TargetRecord> {
        try await startIfNeeded()
        guard let dao else { throw RepositoryError.notReady }
        return dao
    }

    private static func uniqueIds(from uniqueIds: [String]) -> [String] {
        uniqueIds
    }

    private static func clampPosition(_ position: Int) -> Int {
        min(max(position, 0), 100)
    }

    private static func averagePosition(for positions: [Int]) -> Int {
        guard positions.isEmpty == false else { return 0 }
        let sum = positions.reduce(0, +)
        let average = Double(sum) / Double(positions.count)
        return clampPosition(Int(average.rounded()))
    }

    private static func positionPercent(for descriptor: DeviceControlDescriptor) -> Int {
        let lowerBound = descriptor.range.lowerBound
        let upperBound = descriptor.range.upperBound
        guard upperBound > lowerBound else {
            return 0
        }

        let normalized = ((descriptor.value - lowerBound) / (upperBound - lowerBound)) * 100
        return clampPosition(Int(normalized.rounded()))
    }

    private static func formatNumber(_ value: Double) -> String {
        if value.rounded(.towardZero) == value {
            return String(Int(value))
        }
        return String(format: "%.3f", value)
    }

    private static func isFresh(updatedAt: Date?, now: Date) -> Bool {
        guard let updatedAt else { return false }
        return now.timeIntervalSince(updatedAt) <= staleTargetThreshold
    }

    private static func shutterDescriptor(for device: DeviceRecord) -> DeviceControlDescriptor? {
        guard device.group == .shutter else { return nil }
        guard let descriptor = device.primaryControlDescriptor(), descriptor.kind == .slider else {
            return nil
        }
        return descriptor
    }

    private static let createShutterTargetsTableSQL = """
    CREATE TABLE IF NOT EXISTS shutter_targets (
        uniqueId TEXT PRIMARY KEY,
        targetPosition INTEGER NOT NULL CHECK (targetPosition BETWEEN 0 AND 100),
        updatedAt REAL
    );
    """

    private static let addUpdatedAtColumnSQL = """
    ALTER TABLE shutter_targets ADD COLUMN updatedAt REAL;
    """

    private static let staleTargetThreshold: TimeInterval = 60

    private static func hasUpdatedAtColumn(database: SQLiteDatabase) async -> Bool {
        guard let rows = try? await database.query("PRAGMA table_info(shutter_targets);") else {
            return false
        }

        return rows.contains { row in
            guard case .text(let name)? = row.value("name") else {
                return false
            }
            return name == "updatedAt"
        }
    }
}
