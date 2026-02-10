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

    func isEquivalentForUI(to other: ShutterSnapshot) -> Bool {
        uniqueId == other.uniqueId &&
        actualStep == other.actualStep &&
        targetStep == other.targetStep &&
        descriptor.kind == other.descriptor.kind &&
        descriptor.key == other.descriptor.key &&
        descriptor.range == other.descriptor.range
    }

    static func areEquivalentForUI(_ lhs: ShutterSnapshot?, _ rhs: ShutterSnapshot?) -> Bool {
        switch (lhs, rhs) {
        case (.none, .none):
            true
        case let (.some(left), .some(right)):
            left.isEquivalentForUI(to: right)
        default:
            false
        }
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
    private let autoObserveDevices: Bool

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
        autoObserveDevices: Bool = true,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.databasePath = databasePath
        self.deviceRepository = deviceRepository
        self.autoObserveDevices = autoObserveDevices
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
        if autoObserveDevices {
            startObservingDevicesIfNeeded()
        }
    }

    func observeShutter(uniqueId: String) async -> AsyncStream<ShutterSnapshot?> {
        try? await startIfNeeded()
        let observerId = UUID()
        let (stream, continuation) = AsyncStream<ShutterSnapshot?>.makeStream()

        addObserver(id: observerId, uniqueId: uniqueId, continuation: continuation)
        continuation.yield(snapshot(for: uniqueId))
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeObserver(id: observerId) }
        }

        return stream
    }

    func stopObservation() {
        deviceObservationTask?.cancel()
        deviceObservationTask = nil
    }

    func syncDevices(_ devices: [DeviceRecord]) async {
        try? await startIfNeeded()

        var nextDescriptorsById: [String: DeviceControlDescriptor] = [:]

        for device in devices {
            guard let descriptor = Self.shutterDescriptor(for: device) else { continue }
            let uniqueId = device.uniqueId
            nextDescriptorsById[uniqueId] = descriptor

            let previousDescriptor = descriptorsById[uniqueId]
            let newStep = ShutterStep.nearestStep(for: descriptor.value, in: descriptor.range)
            let previousDisplayed = displayedActualById[uniqueId] ?? newStep
            let didShutterControlChange = Self.didShutterControlChange(
                previous: previousDescriptor,
                current: descriptor
            )

            if var uiRecord = uiStateById[uniqueId],
               let target = uiRecord.targetStep.flatMap(ShutterStep.init(rawValue:)) {
                let origin = uiRecord.originStep.flatMap(ShutterStep.init(rawValue:)) ?? previousDisplayed

                if newStep == target && !uiRecord.ignoredEcho && previousDisplayed == origin {
                    uiRecord.ignoredEcho = true
                    uiRecord.updatedAt = now()
                    uiStateById[uniqueId] = uiRecord
                    await upsertUIState(uiRecord)
                    displayedActualById[uniqueId] = previousDisplayed
                } else if newStep == target && uiRecord.ignoredEcho && !didShutterControlChange {
                    // Ignore duplicate echoes coming from unrelated device updates.
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
        let deviceRepository = self.deviceRepository

        deviceObservationTask = Task { [weak self] in
            let stream = await deviceRepository.observeDevices()
            for await devices in stream {
                guard let self else { return }
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

    private static func didShutterControlChange(
        previous: DeviceControlDescriptor?,
        current: DeviceControlDescriptor
    ) -> Bool {
        guard let previous else { return true }
        return previous.kind != current.kind ||
            previous.key != current.key ||
            previous.range != current.range ||
            ShutterStep.nearestStep(for: previous.value, in: previous.range) !=
            ShutterStep.nearestStep(for: current.value, in: current.range)
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
