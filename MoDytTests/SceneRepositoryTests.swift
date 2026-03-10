import Foundation
import Testing
@testable import MoDyt

struct SceneRepositoryTests {
    @Test
    func upsertStoresSceneAndMergesPayloadAcrossUpdates() async throws {
        let databasePath = testTemporarySQLitePath("scene-repository-tests")
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let repository = SceneRepository.makeSceneRepository(databasePath: databasePath)

        try await repository.upsert([
            SceneUpsert(
                id: "scene-1",
                name: "Morning",
                type: "user",
                picto: "sun.max",
                ruleId: "rule-1",
                payload: ["level": .number(25)],
                isGatewayInternal: false
            )
        ])
        try await repository.upsert([
            SceneUpsert(
                id: "scene-1",
                name: "Morning",
                type: "user",
                picto: "sun.max",
                ruleId: "rule-1",
                payload: ["active": .bool(true)],
                isGatewayInternal: false
            )
        ])

        let stored = try await repository.get("scene-1")

        #expect(stored?.name == "Morning")
        #expect(stored?.payload == [
            "level": .number(25),
            "active": .bool(true),
        ])
    }

    @Test
    func gatewayInternalUpsertDeletesExistingScene() async throws {
        let databasePath = testTemporarySQLitePath("scene-repository-tests")
        defer { try? FileManager.default.removeItem(atPath: databasePath) }

        let repository = SceneRepository.makeSceneRepository(databasePath: databasePath)

        try await repository.upsert([
            SceneUpsert(
                id: "scene-2",
                name: "Away",
                type: "user",
                picto: "house",
                ruleId: nil,
                payload: ["enabled": .bool(true)],
                isGatewayInternal: false
            )
        ])
        try await repository.upsert([
            SceneUpsert(
                id: "scene-2",
                name: "Away",
                type: "RE2020",
                picto: "house",
                ruleId: nil,
                payload: [:],
                isGatewayInternal: true
            )
        ])

        #expect(try await repository.get("scene-2") == nil)
    }
}
