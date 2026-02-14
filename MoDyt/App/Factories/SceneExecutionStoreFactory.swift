import SwiftUI

struct SceneExecutionStoreFactory {
    let make: @MainActor (String) -> SceneExecutionStore

    static func live(environment: AppEnvironment) -> SceneExecutionStoreFactory {
        SceneExecutionStoreFactory { uniqueId in
            SceneExecutionStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    executeScene: { uniqueId in
                        await environment.executeScene(uniqueId)
                    }
                )
            )
        }
    }
}

private struct SceneExecutionStoreFactoryKey: EnvironmentKey {
    static var defaultValue: SceneExecutionStoreFactory {
        SceneExecutionStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var sceneExecutionStoreFactory: SceneExecutionStoreFactory {
        get { self[SceneExecutionStoreFactoryKey.self] }
        set { self[SceneExecutionStoreFactoryKey.self] = newValue }
    }
}
