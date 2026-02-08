import Foundation
import DeltaDoreClient
import Persistence

struct ShutterSnapshot: Sendable, Equatable {
    let uniqueId: String
    let descriptor: DeviceControlDescriptor
    let actualStep: ShutterStep
    let targetStep: ShutterStep?

    var effectiveTargetStep: ShutterStep {
        targetStep ?? actualStep
    }

    var isInFlight: Bool {
        guard let targetStep else { return false }
        return actualStep != targetStep
    }
}

actor ShutterRepository {
    enum RepositoryError: Error {
        case notReady
    }

    private struct ShutterUIRecord: Codable, Sendable, Equatable {
        let uniqueId: String
        var targetStep: Int?
        var originStep: Int?
        var ignoredEcho: Bool
        var updatedAt: Date
    }

    private let databasePath: String
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void
    private let deviceRepository: DeviceRepository

    private var database: SQLiteDatabase?
    private var uiStateDAO: DAO<ShutterUIRecord>?
    private var uiStateById: [String: ShutterUIRecord] = [:]
    private var descriptorsById: [String: DeviceControlDescriptor] = [:]
    private var displayedActualById: [String: ShutterStep] = [:]
    private var observers: [UUID: (uniqueId: String, continuation: AsyncStream<ShutterSnapshot?>.Continuation)] = [:]
    private var deviceObservationTask: Task<Void, Never>?

    init(
        databasePath: String,
        deviceRepository: DeviceRepository,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.databasePath = databasePath
        self.deviceRepository = deviceRepository
        self.now = now
        self.log = log
    }

    func startIfNeeded() async throws {
        if uiStateDAO != nil { return }
        let db = try await SQLiteDatabase(path: databasePath)
        try await db.execute(Self.createShutterUIStateTableSQL)
        let schema = TableSchema<ShutterUIRecord>.codable(table: "shutter_ui_state", primaryKey: "uniqueId")
        let dao = DAO.make(database: db, schema: schema)

        let existing = (try? await dao.list()) ?? []

        database = db
        uiStateDAO = dao
        uiStateById = Dictionary(uniqueKeysWithValues: existing.map { ($0.uniqueId, $0) })
        startObservingDevicesIfNeeded()
    }

    func observeShutter(uniqueId: String) async -> AsyncStream<ShutterSnapshot?> {
        try? await startIfNeeded()
        let observerId = UUID()

        return AsyncStream { continuation in
            Task { [weak self] in
                guard let self else {
                    continuation.finish()
                    return
                }
                await self.addObserver(id: observerId, uniqueId: uniqueId, continuation: continuation)
                continuation.yield(await self.snapshot(for: uniqueId))
            }

            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeObserver(id: observerId) }
            }
        }
    }

    func syncDevices(_ devices: [DeviceRecord]) async {
        try? await startIfNeeded()

        var nextDescriptorsById: [String: DeviceControlDescriptor] = [:]

        for device in devices {
            guard let descriptor = Self.shutterDescriptor(for: device) else { continue }
            let uniqueId = device.uniqueId
            nextDescriptorsById[uniqueId] = descriptor

            let newStep = ShutterStep.nearestStep(for: descriptor.value, in: descriptor.range)
            let previousDisplayed = displayedActualById[uniqueId] ?? newStep

            if var uiRecord = uiStateById[uniqueId],
               let target = uiRecord.targetStep.flatMap(ShutterStep.init(rawValue:)) {
                let origin = uiRecord.originStep.flatMap(ShutterStep.init(rawValue:)) ?? previousDisplayed

                if newStep == target && !uiRecord.ignoredEcho && previousDisplayed == origin {
                    uiRecord.ignoredEcho = true
                    uiRecord.updatedAt = now()
                    uiStateById[uniqueId] = uiRecord
                    await upsertUIState(uiRecord)
                    displayedActualById[uniqueId] = previousDisplayed
                } else {
                    displayedActualById[uniqueId] = newStep

                    if newStep == target {
                        uiStateById.removeValue(forKey: uniqueId)
                        await deleteUIState(uniqueId: uniqueId)
                    }
                }
            } else {
                displayedActualById[uniqueId] = newStep
            }
        }

        let removedIds = Set(descriptorsById.keys).subtracting(nextDescriptorsById.keys)
        descriptorsById = nextDescriptorsById

        for uniqueId in removedIds {
            displayedActualById.removeValue(forKey: uniqueId)
            if uiStateById.removeValue(forKey: uniqueId) != nil {
                await deleteUIState(uniqueId: uniqueId)
            }
        }

        await notifyObservers()
    }

    func setTarget(
        uniqueId: String,
        targetStep: ShutterStep,
        originStep: ShutterStep
    ) async {
        try? await startIfNeeded()

        let record = ShutterUIRecord(
            uniqueId: uniqueId,
            targetStep: targetStep.rawValue,
            originStep: originStep.rawValue,
            ignoredEcho: false,
            updatedAt: now()
        )

        uiStateById[uniqueId] = record
        await upsertUIState(record)
        await notifyObservers(for: [uniqueId])
    }

    func clearAll() async {
        try? await startIfNeeded()
        uiStateById.removeAll()
        descriptorsById.removeAll()
        displayedActualById.removeAll()
        if let database {
            try? await database.execute("DELETE FROM shutter_ui_state;")
        }
        await notifyObservers()
    }

    private func startObservingDevicesIfNeeded() {
        guard deviceObservationTask == nil else { return }

        deviceObservationTask = Task { [weak self] in
            guard let self else { return }
            let stream = await self.deviceRepository.observeDevices()
            for await devices in stream {
                await self.syncDevices(devices)
            }
        }
    }

    private func addObserver(
        id: UUID,
        uniqueId: String,
        continuation: AsyncStream<ShutterSnapshot?>.Continuation
    ) {
        observers[id] = (uniqueId: uniqueId, continuation: continuation)
    }

    private func removeObserver(id: UUID) {
        observers[id] = nil
    }

    private func notifyObservers(for uniqueIds: Set<String>? = nil) async {
        for observer in observers.values {
            if let uniqueIds, !uniqueIds.contains(observer.uniqueId) {
                continue
            }
            observer.continuation.yield(snapshot(for: observer.uniqueId))
        }
    }

    private func snapshot(for uniqueId: String) -> ShutterSnapshot? {
        guard let descriptor = descriptorsById[uniqueId] else { return nil }

        let actual = displayedActualById[uniqueId]
            ?? ShutterStep.nearestStep(for: descriptor.value, in: descriptor.range)

        let target = uiStateById[uniqueId]
            .flatMap { $0.targetStep }
            .flatMap(ShutterStep.init(rawValue:))

        return ShutterSnapshot(
            uniqueId: uniqueId,
            descriptor: descriptor,
            actualStep: actual,
            targetStep: target
        )
    }

    private func upsertUIState(_ record: ShutterUIRecord) async {
        guard let uiStateDAO = try? await requireUIStateDAO() else { return }

        if (try? await uiStateDAO.read(.text(record.uniqueId))) == nil {
            _ = try? await uiStateDAO.create(record)
        } else {
            _ = try? await uiStateDAO.update(record)
        }

        log("Upsert shutter ui-state uniqueId=\(record.uniqueId)")
    }

    private func deleteUIState(uniqueId: String) async {
        guard let uiStateDAO = try? await requireUIStateDAO() else { return }
        _ = try? await uiStateDAO.delete(.text(uniqueId))
        log("Delete shutter ui-state uniqueId=\(uniqueId)")
    }

    private func requireUIStateDAO() async throws -> DAO<ShutterUIRecord> {
        try await startIfNeeded()
        guard let uiStateDAO else { throw RepositoryError.notReady }
        return uiStateDAO
    }

    private static func shutterDescriptor(for device: DeviceRecord) -> DeviceControlDescriptor? {
        guard device.group == .shutter else { return nil }
        guard let descriptor = device.primaryControlDescriptor(), descriptor.kind == .slider else { return nil }
        return descriptor
    }

    private static let createShutterUIStateTableSQL = """
    CREATE TABLE IF NOT EXISTS shutter_ui_state (
        uniqueId TEXT PRIMARY KEY,
        targetStep INTEGER,
        originStep INTEGER,
        ignoredEcho INTEGER NOT NULL,
        updatedAt REAL NOT NULL
    );
    """
}
