import SwiftUI

struct ScenesStoreFactory {
    let make: @MainActor () -> ScenesStore

    static func live(environment: AppEnvironment) -> ScenesStoreFactory {
        ScenesStoreFactory {
            ScenesStore(
                dependencies: .init(
                    observeScenes: {
                        await environment.sceneRepository.observeScenes()
                    },
                    toggleFavorite: { uniqueId in
                        await environment.sceneRepository.toggleFavorite(uniqueId: uniqueId)
                    },
                    refreshAll: {
                        await environment.requestRefreshAll()
                    }
                )
            )
        }
    }
}

private struct ScenesStoreFactoryKey: EnvironmentKey {
    static var defaultValue: ScenesStoreFactory {
        ScenesStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var scenesStoreFactory: ScenesStoreFactory {
        get { self[ScenesStoreFactoryKey.self] }
        set { self[ScenesStoreFactoryKey.self] = newValue }
    }
}
