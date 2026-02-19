import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct DashboardRepositoryTests {
    @Test
    func observesFavoritedGroupWhenNoDeviceOrSceneFavoritesExist() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let sceneRepository = SceneRepository(databasePath: databasePath, log: { _ in })
        let groupRepository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )
        let repository = DashboardRepository(
            deviceRepository: deviceRepository,
            sceneRepository: sceneRepository,
            groupRepository: groupRepository
        )

        await groupRepository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 300,
                name: "Volets Jour",
                usage: "shutter",
                picto: nil,
                isGroupUser: true,
                isGroupAll: false,
                payload: [:]
            )
        ], transactionId: nil))
        await groupRepository.applyMessage(.groups([
            TydomGroup(
                id: 300,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 88,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 77)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: nil))
        await groupRepository.toggleFavorite(uniqueId: GroupRecord.uniqueId(for: 300))

        let stream = await repository.observeFavorites()
        var iterator = stream.makeAsyncIterator()
        var latest: [DashboardDeviceDescription] = []

        for _ in 0..<8 {
            guard let next = await iterator.next() else { break }
            latest = next
            if next.count == 1 {
                break
            }
        }

        #expect(latest.count == 1)
        #expect(latest[0].source == .group)
        #expect(latest[0].uniqueId == GroupRecord.uniqueId(for: 300))
        #expect(latest[0].memberUniqueIds == ["77_88"])
    }

    @Test
    func observesMergedFavoritesFromDevicesAndScenes() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let sceneRepository = SceneRepository(databasePath: databasePath, log: { _ in })
        let groupRepository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )
        let repository = DashboardRepository(
            deviceRepository: deviceRepository,
            sceneRepository: sceneRepository,
            groupRepository: groupRepository
        )

        await deviceRepository.upsertDevices([
            TydomDevice(
                id: 1,
                endpointId: 1,
                uniqueId: "1_1",
                name: "Kitchen Light",
                usage: "light",
                kind: .light,
                data: ["on": .bool(false)],
                metadata: nil
            )
        ])
        await sceneRepository.upsertScenes([
            TydomScenario(
                id: 101,
                name: "Away",
                type: "NORMAL",
                picto: "scene",
                ruleId: nil,
                payload: [:]
            )
        ])
        await groupRepository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 201,
                name: "Salon Lights",
                usage: "light",
                picto: nil,
                isGroupUser: true,
                isGroupAll: false,
                payload: [:]
            )
        ], transactionId: nil))
        await groupRepository.applyMessage(.groups([
            TydomGroup(
                id: 201,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 1)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: nil))

        await deviceRepository.toggleFavorite(uniqueId: "1_1")
        await sceneRepository.toggleFavorite(uniqueId: SceneRecord.uniqueId(for: 101))
        await groupRepository.toggleFavorite(uniqueId: GroupRecord.uniqueId(for: 201))

        let stream = await repository.observeFavorites()
        var iterator = stream.makeAsyncIterator()
        var latest: [DashboardDeviceDescription] = []

        for _ in 0..<8 {
            guard let next = await iterator.next() else { break }
            latest = next
            if next.count == 3 {
                break
            }
        }

        #expect(latest.count == 3)
        #expect(latest.map(\.source) == [.device, .scene, .group])
        #expect(latest.map(\.name) == ["Kitchen Light", "Away", "Salon Lights"])
        let groupFavorite = latest.first(where: { $0.source == .group })
        #expect(groupFavorite?.memberUniqueIds == ["1_1"])
    }

    @Test
    func reorderFavoriteSupportsSceneAndDeviceCrossDrop() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let sceneRepository = SceneRepository(databasePath: databasePath, log: { _ in })
        let groupRepository = GroupRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )
        let repository = DashboardRepository(
            deviceRepository: deviceRepository,
            sceneRepository: sceneRepository,
            groupRepository: groupRepository
        )

        await deviceRepository.upsertDevices([
            TydomDevice(
                id: 1,
                endpointId: 1,
                uniqueId: "1_1",
                name: "Kitchen Light",
                usage: "light",
                kind: .light,
                data: ["on": .bool(false)],
                metadata: nil
            )
        ])
        await sceneRepository.upsertScenes([
            TydomScenario(
                id: 101,
                name: "Away",
                type: "NORMAL",
                picto: "scene",
                ruleId: nil,
                payload: [:]
            )
        ])
        await groupRepository.applyMessage(.groupMetadata([
            TydomGroupMetadata(
                id: 201,
                name: "Salon Lights",
                usage: "light",
                picto: nil,
                isGroupUser: true,
                isGroupAll: false,
                payload: [:]
            )
        ], transactionId: nil))
        await groupRepository.applyMessage(.groups([
            TydomGroup(
                id: 201,
                devices: [
                    TydomGroup.DeviceMember(
                        id: 1,
                        endpoints: [TydomGroup.DeviceMember.EndpointMember(id: 1)]
                    )
                ],
                areas: [],
                payload: [:]
            )
        ], transactionId: nil))

        await deviceRepository.toggleFavorite(uniqueId: "1_1")
        await sceneRepository.toggleFavorite(uniqueId: SceneRecord.uniqueId(for: 101))
        await groupRepository.toggleFavorite(uniqueId: GroupRecord.uniqueId(for: 201))

        await repository.reorderFavorite(
            from: GroupRecord.uniqueId(for: 201),
            to: "1_1"
        )

        let deviceFavorites = await deviceRepository.favoriteDescriptionsSnapshot()
        let sceneFavorites = await sceneRepository.favoriteDescriptionsSnapshot()
        let groupFavorites = await groupRepository.favoriteDescriptionsSnapshot()

        #expect(sceneFavorites.count == 1)
        #expect(deviceFavorites.count == 1)
        #expect(groupFavorites.count == 1)
        #expect(groupFavorites[0].dashboardOrder == 0)
        #expect(deviceFavorites[0].dashboardOrder == 1)
        #expect(sceneFavorites[0].dashboardOrder == 2)
    }
}
