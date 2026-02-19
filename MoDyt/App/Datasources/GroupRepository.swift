import Foundation
import DeltaDoreClient
import Persistence

struct GroupFanOutCommand: Sendable, Equatable {
    let deviceId: Int
    let endpointId: Int
    let key: String
    let value: JSONValue
}

actor GroupRepository {
    enum RepositoryError: Error {
        case notReady
    }

    private struct MemberEndpoint {
        let uniqueId: String
        let deviceId: Int
        let endpointId: Int
        let device: DeviceRecord?
    }

    private let databasePath: String
    private let deviceRepository: DeviceRepository
    private let now: @Sendable () -> Date
    private let log: @Sendable (String) -> Void

    private var database: SQLiteDatabase?
    private var dao: DAO<GroupRecord>?
    private var groupsByUniqueId: [String: GroupRecord] = [:]
    private var observers: [UUID: AsyncStream<[GroupRecord]>.Continuation] = [:]
    private var controlObservers: [UUID: (uniqueId: String, continuation: AsyncStream<DeviceRecord?>.Continuation)] = [:]

    private var metadataByGroupId: [Int: TydomGroupMetadata] = [:]
    private var membershipByGroupId: [Int: [String]] = [:]
    private var devicesByUniqueId: [String: DeviceRecord] = [:]
    private var deviceObservationTask: Task<Void, Never>?

    private var optimisticLightDataByUniqueId: [String: [String: JSONValue]] = [:]
    private var optimisticLightSetAtByUniqueId: [String: Date] = [:]

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
        if dao != nil { return }

        let db = try await SQLiteDatabase(path: databasePath)
        try await db.execute(Self.createGroupsTableSQL)
        let schema = TableSchema<GroupRecord>.codable(table: "groups", primaryKey: "uniqueId")
        let groupDAO = DAO.make(database: db, schema: schema)

        let existing = (try? await groupDAO.list()) ?? []
        groupsByUniqueId = Dictionary(uniqueKeysWithValues: existing.map { ($0.uniqueId, $0) })
        membershipByGroupId = Dictionary(uniqueKeysWithValues: existing.map { ($0.groupId, $0.memberUniqueIds) })

        database = db
        dao = groupDAO
        startObservingDevicesIfNeeded()
    }

    func hasAnyData() async -> Bool {
        guard let groupDAO = try? await requireDAO() else { return false }
        let groups = (try? await groupDAO.list()) ?? []
        return groups.isEmpty == false
    }

    func observeGroups() -> AsyncStream<[GroupRecord]> {
        let observerId = UUID()
        let (stream, continuation) = AsyncStream<[GroupRecord]>.makeStream()

        addObserver(id: observerId, continuation: continuation)

        let snapshotTask = Task { [weak self] in
            guard let self else {
                continuation.finish()
                return
            }

            do {
                try await self.startIfNeeded()
                let snapshot = await self.sortedGroups()
                continuation.yield(snapshot)
            } catch {
                log("Groups snapshot load failed error=\(error)")
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
        observeGroups()
            .map { snapshot in
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
        try? await startIfNeeded()
        let groups = sortedGroups()
        return groups
            .filter(\.isFavorite)
            .sorted { lhs, rhs in
                let lhsOrder = lhs.dashboardOrder ?? lhs.favoriteOrder ?? Int.max
                let rhsOrder = rhs.dashboardOrder ?? rhs.favoriteOrder ?? Int.max
                return lhsOrder < rhsOrder
            }
            .map(Self.makeDashboardDescription(from:))
    }

    func listGroups() async throws -> [GroupRecord] {
        _ = try await requireDAO()
        return sortedGroups()
    }

    func toggleFavorite(uniqueId: String) async {
        guard var existing = groupsByUniqueId[uniqueId] else { return }
        guard existing.isGroupUser else { return }
        guard existing.memberUniqueIds.isEmpty == false else { return }

        if existing.isFavorite {
            existing.isFavorite = false
            existing.favoriteOrder = nil
            existing.dashboardOrder = nil
        } else {
            let maxOrder = groupsByUniqueId.values
                .filter(\.isFavorite)
                .compactMap { $0.dashboardOrder ?? $0.favoriteOrder }
                .max() ?? -1
            existing.isFavorite = true
            existing.favoriteOrder = maxOrder + 1
            existing.dashboardOrder = maxOrder + 1
        }

        existing.updatedAt = now()
        await upsertRecord(existing)
        await notifyObservers()
    }

    func applyDashboardOrders(_ orders: [String: Int]) async {
        guard !orders.isEmpty else { return }
        var didUpdate = false

        for (uniqueId, order) in orders {
            guard var existing = groupsByUniqueId[uniqueId] else { continue }
            guard existing.isFavorite else { continue }
            guard existing.dashboardOrder != order || existing.favoriteOrder != order else {
                continue
            }

            existing.dashboardOrder = order
            existing.favoriteOrder = order
            existing.updatedAt = now()
            await upsertRecord(existing)
            didUpdate = true
        }

        if didUpdate {
            await notifyObservers()
        }
    }

    func applyMessage(_ message: TydomMessage) async {
        switch message {
        case .groupMetadata(let metadata, _):
            log("Apply group metadata count=\(metadata.count)")
            await applyGroupMetadata(metadata)
        case .groups(let groups, _):
            log("Apply group membership count=\(groups.count)")
            await applyGroupMembership(groups)
        default:
            break
        }
    }

    func observeGroupControlDevice(uniqueId: String) async -> AsyncStream<DeviceRecord?> {
        try? await startIfNeeded()
        let observerId = UUID()
        let (stream, continuation) = AsyncStream<DeviceRecord?>.makeStream()

        addControlObserver(
            id: observerId,
            uniqueId: uniqueId,
            continuation: continuation
        )
        continuation.yield(groupControlDeviceSnapshot(for: uniqueId))

        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeControlObserver(id: observerId) }
        }

        return stream
    }

    func applyOptimisticControlChanges(
        uniqueId: String,
        changes: [String: JSONValue]
    ) async {
        guard !changes.isEmpty else { return }
        guard let group = groupsByUniqueId[uniqueId] else { return }
        guard group.resolvedGroup == .light else { return }

        var existing = optimisticLightDataByUniqueId[uniqueId] ?? [:]
        for (key, value) in changes {
            existing[key] = value
        }
        optimisticLightDataByUniqueId[uniqueId] = existing
        optimisticLightSetAtByUniqueId[uniqueId] = now()
        await notifyControlObservers(for: [uniqueId])
    }

    func fanOutCommands(
        uniqueId: String,
        key: String,
        value: JSONValue
    ) async -> [GroupFanOutCommand] {
        guard let group = groupsByUniqueId[uniqueId] else { return [] }
        let resolvedGroup = group.resolvedGroup

        switch resolvedGroup {
        case .light:
            return mapLightCommands(for: group, key: key, value: value)
        case .shutter:
            return mapShutterCommands(for: group, key: key, value: value)
        default:
            return mapPassthroughCommands(for: group, key: key, value: value)
        }
    }

    private func applyGroupMetadata(_ metadata: [TydomGroupMetadata]) async {
        _ = try? await requireDAO()

        metadataByGroupId = Dictionary(uniqueKeysWithValues: metadata.map { ($0.id, $0) })
        let incomingIds = Set(metadataByGroupId.keys)
        let existingByGroupId = Dictionary(
            uniqueKeysWithValues: groupsByUniqueId.values.map { ($0.groupId, $0) }
        )

        let removedUniqueIds = groupsByUniqueId.values
            .filter { incomingIds.contains($0.groupId) == false }
            .map(\.uniqueId)
        for uniqueId in removedUniqueIds {
            await deleteRecord(uniqueId: uniqueId)
            optimisticLightDataByUniqueId[uniqueId] = nil
            optimisticLightSetAtByUniqueId[uniqueId] = nil
        }

        for groupMetadata in metadata {
            let existing = existingByGroupId[groupMetadata.id]
            let members = membershipByGroupId[groupMetadata.id] ?? existing?.memberUniqueIds ?? []
            let merged = makeRecord(
                groupId: groupMetadata.id,
                metadata: groupMetadata,
                existing: existing,
                memberUniqueIds: members
            )
            await upsertRecord(merged)
        }

        await notifyObservers()
    }

    private func applyGroupMembership(_ groups: [TydomGroup]) async {
        _ = try? await requireDAO()

        for group in groups {
            membershipByGroupId[group.id] = Self.memberUniqueIds(from: group)
        }

        let existingByGroupId = Dictionary(
            uniqueKeysWithValues: groupsByUniqueId.values.map { ($0.groupId, $0) }
        )

        let allGroupIds = Set(metadataByGroupId.keys)
            .union(existingByGroupId.keys)
            .union(membershipByGroupId.keys)

        for groupId in allGroupIds {
            let existing = existingByGroupId[groupId]
            let metadata = metadataByGroupId[groupId]
            let members = membershipByGroupId[groupId] ?? existing?.memberUniqueIds ?? []
            let merged = makeRecord(
                groupId: groupId,
                metadata: metadata,
                existing: existing,
                memberUniqueIds: members
            )
            await upsertRecord(merged)
        }

        await notifyObservers()
    }

    private func makeRecord(
        groupId: Int,
        metadata: TydomGroupMetadata?,
        existing: GroupRecord?,
        memberUniqueIds: [String]
    ) -> GroupRecord {
        let normalizedMembers = Self.uniqueOrdered(memberUniqueIds)
        let isEmptyGroup = normalizedMembers.isEmpty
        let isUserGroup = metadata?.isGroupUser ?? existing?.isGroupUser ?? false
        let isFavorite = (!isUserGroup || isEmptyGroup) ? false : (existing?.isFavorite ?? false)
        let favoriteOrder = isFavorite ? existing?.favoriteOrder : nil
        let dashboardOrder = isFavorite ? existing?.dashboardOrder : nil

        return GroupRecord(
            uniqueId: GroupRecord.uniqueId(for: groupId),
            groupId: groupId,
            name: metadata?.name ?? existing?.name ?? "Group \(groupId)",
            usage: metadata?.usage ?? existing?.usage ?? "unknown",
            picto: metadata?.picto ?? existing?.picto,
            isGroupUser: isUserGroup,
            isGroupAll: metadata?.isGroupAll ?? existing?.isGroupAll ?? false,
            memberUniqueIds: normalizedMembers,
            isFavorite: isFavorite,
            favoriteOrder: favoriteOrder,
            dashboardOrder: dashboardOrder,
            updatedAt: now()
        )
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

    private func syncDevices(_ devices: [DeviceRecord]) async {
        devicesByUniqueId = Dictionary(uniqueKeysWithValues: devices.map { ($0.uniqueId, $0) })

        // Keep optimistic light state during partial fan-out transitions and
        // release it only once actual member state converges (or override expires).
        reconcileOptimisticLightOverrides()

        await notifyControlObservers()
    }

    private func reconcileOptimisticLightOverrides() {
        let trackedIds = Set(optimisticLightDataByUniqueId.keys)
        for uniqueId in trackedIds {
            guard let group = groupsByUniqueId[uniqueId], group.resolvedGroup == .light else {
                optimisticLightDataByUniqueId[uniqueId] = nil
                optimisticLightSetAtByUniqueId[uniqueId] = nil
                continue
            }

            guard let overrides = optimisticLightDataByUniqueId[uniqueId], !overrides.isEmpty else {
                optimisticLightDataByUniqueId[uniqueId] = nil
                optimisticLightSetAtByUniqueId[uniqueId] = nil
                continue
            }

            if isLightOverrideExpired(uniqueId: uniqueId) {
                optimisticLightDataByUniqueId[uniqueId] = nil
                optimisticLightSetAtByUniqueId[uniqueId] = nil
                continue
            }

            guard let actual = lightDescriptor(for: group) else { continue }
            if isLightOverrideSatisfied(overrides: overrides, actual: actual) {
                optimisticLightDataByUniqueId[uniqueId] = nil
                optimisticLightSetAtByUniqueId[uniqueId] = nil
            }
        }
    }

    private func isLightOverrideExpired(uniqueId: String) -> Bool {
        guard let setAt = optimisticLightSetAtByUniqueId[uniqueId] else { return false }
        return now().timeIntervalSince(setAt) >= Self.optimisticLightOverrideTimeout
    }

    private func isLightOverrideSatisfied(
        overrides: [String: JSONValue],
        actual: DrivingLightControlDescriptor
    ) -> Bool {
        if let rawLevel = overrides["level"]?.numberValue {
            let target = rawLevel > 1 ? min(max(rawLevel / 100, 0), 1) : min(max(rawLevel, 0), 1)
            if abs(actual.normalizedLevel - target) <= Self.optimisticLightNormalizedTolerance {
                return true
            }
            if target <= 0.01 {
                return actual.isOn == false
            }
            if target >= 0.99 {
                return actual.normalizedLevel >= 0.99
            }
            return false
        }

        if let expectedOn = overrides["on"]?.boolValue {
            return actual.isOn == expectedOn
        }

        return true
    }

    private func addObserver(
        id: UUID,
        continuation: AsyncStream<[GroupRecord]>.Continuation
    ) {
        observers[id] = continuation
    }

    private func removeObserver(id: UUID) {
        observers[id] = nil
    }

    private func addControlObserver(
        id: UUID,
        uniqueId: String,
        continuation: AsyncStream<DeviceRecord?>.Continuation
    ) {
        controlObservers[id] = (uniqueId: uniqueId, continuation: continuation)
    }

    private func removeControlObserver(id: UUID) {
        controlObservers[id] = nil
    }

    private func notifyObservers() async {
        let snapshot = sortedGroups()
        for continuation in observers.values {
            continuation.yield(snapshot)
        }
        await notifyControlObservers()
    }

    private func notifyControlObservers(for uniqueIds: Set<String>? = nil) async {
        for observer in controlObservers.values {
            if let uniqueIds, uniqueIds.contains(observer.uniqueId) == false {
                continue
            }
            observer.continuation.yield(groupControlDeviceSnapshot(for: observer.uniqueId))
        }
    }

    private func sortedGroups() -> [GroupRecord] {
        groupsByUniqueId.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    private func groupControlDeviceSnapshot(for uniqueId: String) -> DeviceRecord? {
        guard let group = groupsByUniqueId[uniqueId] else { return nil }
        guard group.resolvedGroup == .light else { return nil }
        guard var descriptor = lightDescriptor(for: group) else { return nil }

        let overrides = optimisticLightDataByUniqueId[uniqueId] ?? [:]
        if let isOn = overrides[descriptor.powerKey ?? "on"]?.boolValue {
            descriptor = DrivingLightControlDescriptor(
                powerKey: descriptor.powerKey,
                levelKey: descriptor.levelKey,
                isOn: isOn,
                level: descriptor.level,
                range: descriptor.range
            )
        }
        if let rawLevel = overrides[descriptor.levelKey ?? "level"]?.numberValue {
            let clamped = min(max(rawLevel, descriptor.range.lowerBound), descriptor.range.upperBound)
            descriptor = DrivingLightControlDescriptor(
                powerKey: descriptor.powerKey,
                levelKey: descriptor.levelKey,
                isOn: clamped > descriptor.range.lowerBound,
                level: clamped,
                range: descriptor.range
            )
        }

        var data: [String: JSONValue] = [:]
        data[descriptor.powerKey ?? "on"] = .bool(descriptor.isOn)
        data[descriptor.levelKey ?? "level"] = .number(descriptor.level)
        for (key, value) in overrides {
            data[key] = value
        }

        return DeviceRecord(
            uniqueId: group.uniqueId,
            deviceId: group.groupId,
            endpointId: group.groupId,
            name: group.name,
            usage: group.usage,
            kind: DeviceGroup.from(usage: group.usage).rawValue,
            data: data,
            metadata: nil,
            isFavorite: group.isFavorite,
            favoriteOrder: group.favoriteOrder,
            dashboardOrder: group.dashboardOrder,
            updatedAt: group.updatedAt
        )
    }

    private func lightDescriptor(for group: GroupRecord) -> DrivingLightControlDescriptor? {
        let descriptors = group.memberUniqueIds
            .compactMap { memberUniqueId in
                devicesByUniqueId[memberUniqueId]?.drivingLightControlDescriptor()
            }
        guard descriptors.isEmpty == false else { return nil }

        let maxNormalized = descriptors.reduce(0.0) { partial, descriptor in
            max(partial, descriptor.normalizedLevel)
        }
        let level = min(max(maxNormalized, 0), 1) * 100

        return DrivingLightControlDescriptor(
            powerKey: "on",
            levelKey: "level",
            isOn: maxNormalized > 0.01,
            level: level,
            range: 0...100
        )
    }

    private func mapPassthroughCommands(
        for group: GroupRecord,
        key: String,
        value: JSONValue
    ) -> [GroupFanOutCommand] {
        resolveMemberEndpoints(for: group).map { member in
            GroupFanOutCommand(
                deviceId: member.deviceId,
                endpointId: member.endpointId,
                key: key,
                value: value
            )
        }
    }

    private func mapLightCommands(
        for group: GroupRecord,
        key: String,
        value: JSONValue
    ) -> [GroupFanOutCommand] {
        let members = resolveMemberEndpoints(for: group)
        guard members.isEmpty == false else { return [] }

        if key == "on" {
            let desiredOn = value.boolValue ?? ((value.numberValue ?? 0) > 0.01)
            return members.flatMap { member -> [GroupFanOutCommand] in
                guard let descriptor = member.device?.drivingLightControlDescriptor() else {
                    return [GroupFanOutCommand(
                        deviceId: member.deviceId,
                        endpointId: member.endpointId,
                        key: key,
                        value: .bool(desiredOn)
                    )]
                }

                if let powerKey = descriptor.powerKey {
                    return [GroupFanOutCommand(
                        deviceId: member.deviceId,
                        endpointId: member.endpointId,
                        key: powerKey,
                        value: .bool(desiredOn)
                    )]
                }

                if let levelKey = descriptor.levelKey {
                    let target = desiredOn ? descriptor.range.upperBound : descriptor.range.lowerBound
                    return [GroupFanOutCommand(
                        deviceId: member.deviceId,
                        endpointId: member.endpointId,
                        key: levelKey,
                        value: .number(target)
                    )]
                }

                return [GroupFanOutCommand(
                    deviceId: member.deviceId,
                    endpointId: member.endpointId,
                    key: key,
                    value: .bool(desiredOn)
                )]
            }
        }

        if key == "level" {
            let normalized = Self.normalizedValueForGroupControl(value)
            let desiredOn = normalized > 0.01

            return members.flatMap { member -> [GroupFanOutCommand] in
                guard let descriptor = member.device?.drivingLightControlDescriptor() else {
                    return [GroupFanOutCommand(
                        deviceId: member.deviceId,
                        endpointId: member.endpointId,
                        key: key,
                        value: .number(normalized * 100)
                    )]
                }

                var commands: [GroupFanOutCommand] = []
                if let levelKey = descriptor.levelKey {
                    let target = descriptor.range.lowerBound
                        + (descriptor.range.upperBound - descriptor.range.lowerBound) * normalized
                    commands.append(GroupFanOutCommand(
                        deviceId: member.deviceId,
                        endpointId: member.endpointId,
                        key: levelKey,
                        value: .number(target)
                    ))
                } else if let powerKey = descriptor.powerKey {
                    commands.append(GroupFanOutCommand(
                        deviceId: member.deviceId,
                        endpointId: member.endpointId,
                        key: powerKey,
                        value: .bool(desiredOn)
                    ))
                } else {
                    commands.append(GroupFanOutCommand(
                        deviceId: member.deviceId,
                        endpointId: member.endpointId,
                        key: key,
                        value: .number(normalized * 100)
                    ))
                }

                if let powerKey = descriptor.powerKey, descriptor.levelKey != nil {
                    commands.append(GroupFanOutCommand(
                        deviceId: member.deviceId,
                        endpointId: member.endpointId,
                        key: powerKey,
                        value: .bool(desiredOn)
                    ))
                }

                return commands
            }
        }

        return mapPassthroughCommands(for: group, key: key, value: value)
    }

    private func mapShutterCommands(
        for group: GroupRecord,
        key: String,
        value: JSONValue
    ) -> [GroupFanOutCommand] {
        let members = resolveMemberEndpoints(for: group)
        guard members.isEmpty == false else { return [] }

        guard key == "level" else {
            return mapPassthroughCommands(for: group, key: key, value: value)
        }

        let normalized = Self.normalizedValueForGroupControl(value)
        return members.map { member in
            if let descriptor = member.device?.primaryControlDescriptor(),
               descriptor.kind == .slider {
                let target = descriptor.range.lowerBound
                    + (descriptor.range.upperBound - descriptor.range.lowerBound) * normalized
                return GroupFanOutCommand(
                    deviceId: member.deviceId,
                    endpointId: member.endpointId,
                    key: descriptor.key,
                    value: .number(target)
                )
            }

            return GroupFanOutCommand(
                deviceId: member.deviceId,
                endpointId: member.endpointId,
                key: key,
                value: .number(normalized * 100)
            )
        }
    }

    private func resolveMemberEndpoints(for group: GroupRecord) -> [MemberEndpoint] {
        group.memberUniqueIds.compactMap { memberUniqueId in
            guard let parsed = Self.parseMemberUniqueId(memberUniqueId) else { return nil }
            let resolvedDevice = devicesByUniqueId[memberUniqueId]
            return MemberEndpoint(
                uniqueId: memberUniqueId,
                deviceId: resolvedDevice?.deviceId ?? parsed.deviceId,
                endpointId: resolvedDevice?.endpointId ?? parsed.endpointId,
                device: resolvedDevice
            )
        }
    }

    private func upsertRecord(_ record: GroupRecord) async {
        guard let groupDAO = try? await requireDAO() else { return }

        if groupsByUniqueId[record.uniqueId] == nil {
            _ = try? await groupDAO.create(record)
        } else {
            _ = try? await groupDAO.update(record)
        }

        groupsByUniqueId[record.uniqueId] = record
        membershipByGroupId[record.groupId] = record.memberUniqueIds
    }

    private func deleteRecord(uniqueId: String) async {
        guard let groupDAO = try? await requireDAO() else { return }
        guard let existing = groupsByUniqueId.removeValue(forKey: uniqueId) else { return }
        membershipByGroupId[existing.groupId] = nil
        optimisticLightDataByUniqueId[uniqueId] = nil
        optimisticLightSetAtByUniqueId[uniqueId] = nil
        _ = try? await groupDAO.delete(.text(uniqueId))
    }

    private func requireDAO() async throws -> DAO<GroupRecord> {
        try await startIfNeeded()
        guard let dao else { throw RepositoryError.notReady }
        return dao
    }

    private static func makeDashboardDescription(from group: GroupRecord) -> DashboardDeviceDescription {
        DashboardDeviceDescription(
            uniqueId: group.uniqueId,
            name: group.name,
            usage: group.usage,
            resolvedGroup: DeviceGroup.from(usage: group.usage),
            dashboardOrder: group.dashboardOrder ?? group.favoriteOrder,
            source: .group,
            memberUniqueIds: group.memberUniqueIds
        )
    }

    private static func parseMemberUniqueId(_ uniqueId: String) -> (endpointId: Int, deviceId: Int)? {
        let components = uniqueId.split(separator: "_")
        guard components.count == 2,
              let endpointId = Int(components[0]),
              let deviceId = Int(components[1]) else {
            return nil
        }
        return (endpointId, deviceId)
    }

    private static func normalizedValueForGroupControl(_ value: JSONValue) -> Double {
        if let boolValue = value.boolValue {
            return boolValue ? 1 : 0
        }
        if let number = value.numberValue {
            if number > 1 {
                return min(max(number / 100, 0), 1)
            }
            return min(max(number, 0), 1)
        }
        if let string = value.stringValue, let number = Double(string) {
            if number > 1 {
                return min(max(number / 100, 0), 1)
            }
            return min(max(number, 0), 1)
        }
        return 0
    }

    private static func memberUniqueIds(from group: TydomGroup) -> [String] {
        var memberIds: [String] = []
        for device in group.devices {
            if device.endpoints.isEmpty {
                memberIds.append("\(device.id)_\(device.id)")
                continue
            }

            for endpoint in device.endpoints {
                memberIds.append("\(endpoint.id)_\(device.id)")
            }
        }
        return uniqueOrdered(memberIds)
    }

    private static func uniqueOrdered(_ values: [String]) -> [String] {
        var seen = Set<String>()
        var result: [String] = []
        for value in values where !seen.contains(value) {
            seen.insert(value)
            result.append(value)
        }
        return result
    }

    private static let optimisticLightOverrideTimeout: TimeInterval = 2.5
    private static let optimisticLightNormalizedTolerance: Double = 0.03

    private static let createGroupsTableSQL = """
    CREATE TABLE IF NOT EXISTS groups (
        uniqueId TEXT PRIMARY KEY,
        groupId INTEGER NOT NULL,
        name TEXT NOT NULL,
        usage TEXT NOT NULL,
        picto TEXT,
        isGroupUser INTEGER NOT NULL,
        isGroupAll INTEGER NOT NULL,
        memberUniqueIds TEXT NOT NULL,
        isFavorite INTEGER NOT NULL,
        favoriteOrder INTEGER,
        dashboardOrder INTEGER,
        updatedAt REAL NOT NULL
    );
    """
}
