import Foundation
import Testing
@testable import MoDyt

struct FavoriteRepositoryTests {
    @Test
    func listAllMergesFavoritesAcrossSourcesAndSortsByOrderSourceAndName() async throws {
        let fixture = RepositoryFixture(directoryName: "favorite-repository-tests")
        defer { fixture.cleanup() }

        try await fixture.seedDevice(
            id: .init(deviceId: 1, endpointId: 1),
            name: "Desk Lamp"
        )
        try await fixture.seedGroup(
            id: "group-1",
            name: "Scenes Group",
            usage: "light"
        )
        try await fixture.seedScene(
            id: "scene-1",
            name: "Good Night"
        )

        try await fixture.deviceRepository.toggleFavorite(.init(deviceId: 1, endpointId: 1))
        try await fixture.groupRepository.toggleFavorite("group-1")
        try await fixture.sceneRepository.toggleFavorite("scene-1")

        try await fixture.deviceRepository.applyDashboardOrders([
            .init(deviceId: 1, endpointId: 1): 0
        ])
        try await fixture.sceneRepository.applyDashboardOrders([
            "scene-1": 0
        ])
        try await fixture.groupRepository.applyDashboardOrders([
            "group-1": 0
        ])

        let favorites = try await fixture.favoriteRepository.listAll()

        #expect(favorites.map(\.type) == [
            .device(identifier: .init(deviceId: 1, endpointId: 1)),
            .scene(sceneId: "scene-1"),
            .group(groupId: "group-1", memberIdentifiers: [.init(deviceId: 5, endpointId: 1)]),
        ])
    }

    @Test
    func reorderMovesSourceBeforeTargetAndMissingTargetIsANoOp() async throws {
        let fixture = RepositoryFixture(directoryName: "favorite-repository-tests")
        defer { fixture.cleanup() }

        try await fixture.seedDevice(
            id: .init(deviceId: 1, endpointId: 1),
            name: "Desk Lamp"
        )
        try await fixture.seedScene(
            id: "scene-1",
            name: "Evening"
        )
        try await fixture.seedGroup(
            id: "group-1",
            name: "All Lights",
            usage: "light"
        )

        try await fixture.favoriteRepository.toggleFavorite(.device(identifier: .init(deviceId: 1, endpointId: 1)))
        try await fixture.favoriteRepository.toggleFavorite(.scene(sceneId: "scene-1"))
        try await fixture.favoriteRepository.toggleFavorite(.group(groupId: "group-1", memberIdentifiers: [.init(deviceId: 5, endpointId: 1)]))

        try await fixture.favoriteRepository.reorder(
            .group(groupId: "group-1", memberIdentifiers: [.init(deviceId: 5, endpointId: 1)]),
            .device(identifier: .init(deviceId: 1, endpointId: 1))
        )

        let reordered = try await fixture.favoriteRepository.listAll()
        #expect(reordered.map(\.type) == [
            .group(groupId: "group-1", memberIdentifiers: [.init(deviceId: 5, endpointId: 1)]),
            .device(identifier: .init(deviceId: 1, endpointId: 1)),
            .scene(sceneId: "scene-1"),
        ])

        try await fixture.favoriteRepository.reorder(
            .scene(sceneId: "missing"),
            .device(identifier: .init(deviceId: 1, endpointId: 1))
        )

        let afterNoOp = try await fixture.favoriteRepository.listAll()
        #expect(afterNoOp == reordered)
    }

    @Test
    func toggleFavoriteDelegatesToUnderlyingRepositories() async throws {
        let fixture = RepositoryFixture(directoryName: "favorite-repository-tests")
        defer { fixture.cleanup() }

        try await fixture.seedDevice(
            id: .init(deviceId: 2, endpointId: 1),
            name: "Hallway"
        )
        try await fixture.seedGroup(
            id: "group-2",
            name: "Upstairs",
            usage: "shutter"
        )
        try await fixture.seedScene(
            id: "scene-2",
            name: "Wake Up"
        )

        try await fixture.favoriteRepository.toggleFavorite(.device(identifier: .init(deviceId: 2, endpointId: 1)))
        try await fixture.favoriteRepository.toggleFavorite(.group(groupId: "group-2", memberIdentifiers: [.init(deviceId: 5, endpointId: 1)]))
        try await fixture.favoriteRepository.toggleFavorite(.scene(sceneId: "scene-2"))

        #expect(try await fixture.deviceRepository.get(.init(deviceId: 2, endpointId: 1))?.isFavorite == true)
        #expect(try await fixture.groupRepository.get("group-2")?.isFavorite == true)
        #expect(try await fixture.sceneRepository.get("scene-2")?.isFavorite == true)
    }

    @Test
    func removeFavoriteDoesNothingWhenAlreadyAbsentAndRemovesWhenPresent() async throws {
        let fixture = RepositoryFixture(directoryName: "favorite-repository-tests")
        defer { fixture.cleanup() }

        try await fixture.seedDevice(
            id: .init(deviceId: 9, endpointId: 1),
            name: "Kitchen"
        )
        try await fixture.seedScene(
            id: "scene-9",
            name: "Sleep"
        )

        try await fixture.favoriteRepository.toggleFavorite(.scene(sceneId: "scene-9"))
        try await fixture.favoriteRepository.removeFavorite(.device(identifier: .init(deviceId: 9, endpointId: 1)))
        try await fixture.favoriteRepository.removeFavorite(.scene(sceneId: "scene-9"))

        #expect(try await fixture.deviceRepository.get(.init(deviceId: 9, endpointId: 1))?.isFavorite == false)
        #expect(try await fixture.sceneRepository.get("scene-9")?.isFavorite == false)
    }
}

private struct RepositoryFixture {
    let databasePath: String
    let deviceRepository: DeviceRepository
    let groupRepository: GroupRepository
    let sceneRepository: SceneRepository
    let favoriteRepository: FavoriteRepository

    init(directoryName: String) {
        self.databasePath = testTemporarySQLitePath(directoryName)
        self.deviceRepository = DeviceRepository.makeDeviceRepository(databasePath: databasePath)
        self.groupRepository = GroupRepository.makeGroupRepository(databasePath: databasePath)
        self.sceneRepository = SceneRepository.makeSceneRepository(databasePath: databasePath)
        self.favoriteRepository = FavoriteRepository(
            deviceRepository: deviceRepository,
            groupRepository: groupRepository,
            sceneRepository: sceneRepository
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: databasePath)
    }

    func seedDevice(
        id: DeviceIdentifier,
        name: String
    ) async throws {
        try await deviceRepository.upsert([
            DeviceUpsert(
                id: id,
                name: name,
                usage: "light",
                kind: "light",
                data: ["level": .number(50)],
                metadata: nil
            )
        ])
    }

    func seedGroup(
        id: String,
        name: String,
        usage: String
    ) async throws {
        try await groupRepository.upsertMetadata([
            GroupMetadataUpsert(
                id: id,
                name: name,
                usage: usage,
                picto: nil,
                isGroupUser: true,
                isGroupAll: false
            )
        ])
        try await groupRepository.upsertMembership([
            GroupMembershipUpsert(
                id: id,
                memberIdentifiers: [.init(deviceId: 5, endpointId: 1)]
            )
        ])
    }

    func seedScene(
        id: String,
        name: String
    ) async throws {
        try await sceneRepository.upsert([
            SceneUpsert(
                id: id,
                name: name,
                type: "user",
                picto: "sparkles",
                ruleId: nil,
                payload: ["enabled": .bool(true)],
                isGatewayInternal: false
            )
        ])
    }
}
