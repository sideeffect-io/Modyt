import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct GroupRepositoryTests {
    @Test
    func applyMessages_mergesMetadataWithMembership() async throws {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )

        await repository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 1773652822,
                name: "Volets Jour",
                usage: "shutter",
                picto: "picto_shutter",
                isGroupUser: true,
                isGroupAll: false,
                payload: [:]
            )
        ], transactionId: "gm-1"))
        await repository.applyMessage(.groups([
            TydomGroup(
                id: 1773652822,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1757535455,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 1757535455)]
                    ),
                    TydomGroup.DeviceMember(
                        id: 1757535917,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 1757535917)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: "g-1"))

        let groups = try await repository.listGroups()

        #expect(groups.count == 1)
        #expect(groups[0].groupId == 1773652822)
        #expect(groups[0].name == "Volets Jour")
        #expect(groups[0].usage == "shutter")
        #expect(groups[0].memberUniqueIds == ["1757535455_1757535455", "1757535917_1757535917"])
    }

    @Test
    func partialMembershipUpdate_doesNotClearUnmentionedGroupMembers() async throws {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )

        await repository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 1,
                name: "Group A",
                usage: "shutter",
                picto: nil,
                isGroupUser: true,
                isGroupAll: false,
                payload: [:]
            ),
            TydomGroupMetadata(
                id: 2,
                name: "Group B",
                usage: "shutter",
                picto: nil,
                isGroupUser: true,
                isGroupAll: false,
                payload: [:]
            )
        ], transactionId: "gm-partial"))

        await repository.applyMessage(.groups([
            TydomGroup(
                id: 1,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1001,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 2001)]
                    )
                ],
                areas: [],
                payload: [:]
            ),
            TydomGroup(
                id: 2,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1002,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 2002)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: "g-initial"))

        await repository.applyMessage(.groups([
            TydomGroup(
                id: 1,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1001,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 2001)]
                    ),
                    TydomGroup.DeviceMember(
                        id: 1003,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 2003)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: "g-partial"))

        let groups = try await repository.listGroups()
        let sortedGroups = groups.sorted { $0.groupId < $1.groupId }
        #expect(sortedGroups.count == 2)
        #expect(sortedGroups[0].groupId == 1)
        #expect(sortedGroups[0].memberUniqueIds == ["2001_1001", "2003_1003"])
        #expect(sortedGroups[1].groupId == 2)
        #expect(sortedGroups[1].memberUniqueIds == ["2002_1002"])
    }

    @Test
    func emptyMembershipClearsFavoriteAndPreventsRetoggle() async throws {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )
        let uniqueId = GroupRecord.uniqueId(for: 1722950600)

        await repository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 1722950600,
                name: "Arriere TV",
                usage: "light",
                picto: "picto_lamp",
                isGroupUser: true,
                isGroupAll: false,
                payload: [:]
            )
        ], transactionId: "gm-2"))
        await repository.applyMessage(.groups([
            TydomGroup(
                id: 1722950600,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1757536792,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 1757536792)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: "g-2"))

        await repository.toggleFavorite(uniqueId: uniqueId)
        var groups = try await repository.listGroups()
        #expect(groups[0].isFavorite == true)

        await repository.applyMessage(.groups([
            TydomGroup(
                id: 1722950600,
                devices: [],
                areas: [],
                payload: [:]
            )
        ], transactionId: "g-3"))

        groups = try await repository.listGroups()
        #expect(groups.count == 1)
        #expect(groups[0].memberUniqueIds.isEmpty)
        #expect(groups[0].isFavorite == false)
        #expect(groups[0].favoriteOrder == nil)
        #expect(groups[0].dashboardOrder == nil)

        await repository.toggleFavorite(uniqueId: uniqueId)
        groups = try await repository.listGroups()
        #expect(groups[0].isFavorite == false)
    }

    @Test
    func aggregatedLightSnapshotUsesMaxNormalizedLevel() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )
        let groupUniqueId = GroupRecord.uniqueId(for: 12932271)
        try? await deviceRepository.startIfNeeded()
        try? await repository.startIfNeeded()

        await repository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 12932271,
                name: "TOTAL",
                usage: "light",
                picto: nil,
                isGroupUser: false,
                isGroupAll: true,
                payload: [:]
            )
        ], transactionId: "gm-3"))
        await repository.applyMessage(.groups([
            TydomGroup(
                id: 12932271,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 2)]
                    ),
                    TydomGroup.DeviceMember(
                        id: 1,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 3)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: "g-4"))

        let stream = await repository.observeGroupControlDevice(uniqueId: groupUniqueId)
        let recorder = TestRecorder<DeviceRecord?>()
        let observationTask = Task {
            for await snapshot in stream {
                await recorder.record(snapshot)
            }
        }
        defer { observationTask.cancel() }

        let didStartObserving = await waitUntil(timeout: .seconds(3)) {
            (await recorder.values).isEmpty == false
        }
        #expect(didStartObserving)

        let devices = [
            TydomDevice(
                id: 1,
                endpointId: 2,
                uniqueId: "2_1",
                name: "Light A",
                usage: "light",
                kind: .light,
                data: ["on": .bool(true), "level": .number(100)],
                metadata: nil
            ),
            TydomDevice(
                id: 1,
                endpointId: 3,
                uniqueId: "3_1",
                name: "Light B",
                usage: "light",
                kind: .light,
                data: ["on": .bool(false), "level": .number(0)],
                metadata: nil
            )
        ]

        await deviceRepository.upsertDevices(devices)

        let didReceiveSnapshot = await waitUntil(timeout: .seconds(3)) {
            let snapshots = await recorder.values
            let latest = snapshots.compactMap { $0 }.last
            let descriptor = latest?.drivingLightControlDescriptor()
            return descriptor?.isOn == true && descriptor?.normalizedLevel == 1.0
        }
        #expect(didReceiveSnapshot)

        let snapshot = (await recorder.values).compactMap { $0 }.last

        let descriptor = snapshot?.drivingLightControlDescriptor()
        #expect(descriptor != nil)
        #expect(descriptor?.isOn == true)
        #expect((descriptor?.normalizedLevel ?? 0) == 1.0)
    }

    @Test
    func internalGroupsCannotBeFavorited() async throws {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )
        let uniqueId = GroupRecord.uniqueId(for: 12932271)

        await repository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 12932271,
                name: "TOTAL",
                usage: "light",
                picto: nil,
                isGroupUser: false,
                isGroupAll: true,
                payload: [:]
            )
        ], transactionId: "gm-internal"))
        await repository.applyMessage(.groups([
            TydomGroup(
                id: 12932271,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1757536792,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 1757536792)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: "g-internal"))

        await repository.toggleFavorite(uniqueId: uniqueId)
        let groups = try await repository.listGroups()
        #expect(groups.count == 1)
        #expect(groups[0].isGroupUser == false)
        #expect(groups[0].isFavorite == false)
    }

    @Test
    func optimisticGroupOffHoldsUntilAllMembersReachTarget() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )
        let groupUniqueId = GroupRecord.uniqueId(for: 1722950600)
        try? await deviceRepository.startIfNeeded()
        try? await repository.startIfNeeded()

        await repository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 1722950600,
                name: "Arriere TV",
                usage: "light",
                picto: nil,
                isGroupUser: true,
                isGroupAll: false,
                payload: [:]
            )
        ], transactionId: "gm-off"))
        await repository.applyMessage(.groups([
            TydomGroup(
                id: 1722950600,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1001,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 2001)]
                    ),
                    TydomGroup.DeviceMember(
                        id: 1002,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 2002)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: "g-off"))

        let stream = await repository.observeGroupControlDevice(uniqueId: groupUniqueId)
        let recorder = TestRecorder<DeviceRecord?>()
        let observationTask = Task {
            for await snapshot in stream {
                await recorder.record(snapshot)
            }
        }
        defer { observationTask.cancel() }

        let didStartObserving = await waitUntil(timeout: .seconds(3)) {
            (await recorder.values).isEmpty == false
        }
        #expect(didStartObserving)

        await deviceRepository.upsertDevices([
            TydomDevice(
                id: 1001,
                endpointId: 2001,
                uniqueId: "2001_1001",
                name: "TV Left",
                usage: "light",
                kind: .light,
                data: ["on": .bool(true), "level": .number(100)],
                metadata: nil
            ),
            TydomDevice(
                id: 1002,
                endpointId: 2002,
                uniqueId: "2002_1002",
                name: "TV Right",
                usage: "light",
                kind: .light,
                data: ["on": .bool(true), "level": .number(100)],
                metadata: nil
            )
        ])

        let hasBaselineOnSnapshot = await waitUntil(timeout: .seconds(3)) {
            let snapshots = await recorder.values
            let latest = snapshots.compactMap { $0 }.last
            let descriptor = latest?.drivingLightControlDescriptor()
            return descriptor?.isOn == true && descriptor?.normalizedLevel == 1.0
        }
        #expect(hasBaselineOnSnapshot)

        await repository.applyOptimisticControlChanges(
            uniqueId: groupUniqueId,
            changes: ["on": .bool(false), "level": .number(0)]
        )

        await deviceRepository.upsertDevices([
            TydomDevice(
                id: 1001,
                endpointId: 2001,
                uniqueId: "2001_1001",
                name: "TV Left",
                usage: "light",
                kind: .light,
                data: ["on": .bool(false), "level": .number(0)],
                metadata: nil
            ),
            TydomDevice(
                id: 1002,
                endpointId: 2002,
                uniqueId: "2002_1002",
                name: "TV Right",
                usage: "light",
                kind: .light,
                data: ["on": .bool(true), "level": .number(50)],
                metadata: nil
            )
        ])
        let didReceivePartial = await waitUntil(timeout: .seconds(3)) {
            let snapshots = await recorder.values
            let latest = snapshots.compactMap { $0 }.last
            return latest?.drivingLightControlDescriptor()?.normalizedLevel == 0
        }
        #expect(didReceivePartial)

        let partialSnapshot = (await recorder.values).compactMap { $0 }.last

        #expect(partialSnapshot?.drivingLightControlDescriptor()?.normalizedLevel == 0)

        let countBeforeFinal = (await recorder.values).count

        await deviceRepository.upsertDevices([
            TydomDevice(
                id: 1001,
                endpointId: 2001,
                uniqueId: "2001_1001",
                name: "TV Left",
                usage: "light",
                kind: .light,
                data: ["on": .bool(false), "level": .number(0)],
                metadata: nil
            ),
            TydomDevice(
                id: 1002,
                endpointId: 2002,
                uniqueId: "2002_1002",
                name: "TV Right",
                usage: "light",
                kind: .light,
                data: ["on": .bool(false), "level": .number(0)],
                metadata: nil
            )
        ])
        let didReceiveFinal = await waitUntil(timeout: .seconds(3)) {
            (await recorder.values).count > countBeforeFinal
        }
        #expect(didReceiveFinal)

        let finalSnapshot = (await recorder.values).compactMap { $0 }.last

        #expect(finalSnapshot?.drivingLightControlDescriptor()?.normalizedLevel == 0)
        #expect(finalSnapshot?.drivingLightControlDescriptor()?.isOn == false)
    }

}
