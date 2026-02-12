import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct DashboardRepositoryTests {
    @Test
    func observesMergedFavoritesFromDevicesAndScenes() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let sceneRepository = SceneRepository(databasePath: databasePath, log: { _ in })
        let repository = DashboardRepository(
            deviceRepository: deviceRepository,
            sceneRepository: sceneRepository
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

        await deviceRepository.toggleFavorite(uniqueId: "1_1")
        await sceneRepository.toggleFavorite(uniqueId: SceneRecord.uniqueId(for: 101))

        let stream = await repository.observeFavorites()
        var iterator = stream.makeAsyncIterator()
        var latest: [DashboardDeviceDescription] = []

        for _ in 0..<8 {
            guard let next = await iterator.next() else { break }
            latest = next
            if next.count == 2 {
                break
            }
        }

        #expect(latest.count == 2)
        #expect(latest.map(\.source) == [.device, .scene])
        #expect(latest.map(\.name) == ["Kitchen Light", "Away"])
    }

    @Test
    func reorderFavoriteSupportsSceneAndDeviceCrossDrop() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let sceneRepository = SceneRepository(databasePath: databasePath, log: { _ in })
        let repository = DashboardRepository(
            deviceRepository: deviceRepository,
            sceneRepository: sceneRepository
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

        await deviceRepository.toggleFavorite(uniqueId: "1_1")
        await sceneRepository.toggleFavorite(uniqueId: SceneRecord.uniqueId(for: 101))

        await repository.reorderFavorite(
            from: SceneRecord.uniqueId(for: 101),
            to: "1_1"
        )

        let deviceFavorites = await deviceRepository.favoriteDescriptionsSnapshot()
        let sceneFavorites = await sceneRepository.favoriteDescriptionsSnapshot()

        #expect(sceneFavorites.count == 1)
        #expect(deviceFavorites.count == 1)
        #expect(sceneFavorites[0].dashboardOrder == 0)
        #expect(deviceFavorites[0].dashboardOrder == 1)
    }
}
