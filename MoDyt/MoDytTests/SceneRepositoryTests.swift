import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct SceneRepositoryTests {
    @Test
    func upsertScenes_ignoresGatewayInternalScenes() async throws {
        let repository = SceneRepository(
            databasePath: TestSupport.temporaryDatabasePath(),
            log: { _ in }
        )

        await repository.upsertScenes([
            TydomScenario(
                id: 101,
                name: "Ambiance Film",
                type: "NORMAL",
                picto: "picto_scenario_tv",
                ruleId: nil,
                payload: [:]
            ),
            TydomScenario(
                id: 102,
                name: "TWC_DOWN",
                type: "RE2020",
                picto: "picto_scenario_clap",
                ruleId: nil,
                payload: [:]
            )
        ])

        let scenes = try await repository.listScenes()

        #expect(scenes.count == 1)
        #expect(scenes[0].sceneId == 101)
        #expect(scenes[0].name == "Ambiance Film")
    }

    @Test
    func upsertScenes_removesExistingSceneWhenMarkedAsInternal() async throws {
        let repository = SceneRepository(
            databasePath: TestSupport.temporaryDatabasePath(),
            log: { _ in }
        )

        await repository.upsertScenes([
            TydomScenario(
                id: 201,
                name: "Temp Scene",
                type: "NORMAL",
                picto: "picto_scenario_day",
                ruleId: nil,
                payload: [:]
            )
        ])

        await repository.upsertScenes([
            TydomScenario(
                id: 201,
                name: "TWC_STOP",
                type: "RE2020",
                picto: "picto_scenario_clap",
                ruleId: nil,
                payload: [:]
            )
        ])

        let scenes = try await repository.listScenes()

        #expect(scenes.isEmpty)
    }
}
