import SwiftUI
import DeltaDoreClient

struct ScenesStoreFactory {
    let make: @MainActor () -> ScenesStore

    static func live(dependencies: DependencyBag) -> ScenesStoreFactory {
        let sceneRepository = dependencies.localStorageDatasources.sceneRepository
        let gatewayClient = dependencies.gatewayClient

        return ScenesStoreFactory {
            ScenesStore(
                dependencies: .init(
                    observeScenes: { await sceneRepository.observeAll() },
                    toggleFavorite: { sceneID in try? await sceneRepository.toggleFavorite(sceneID) },
                    refreshAll: { try? await gatewayClient.send(text: TydomCommand.refreshAll().request) }
                )
            )
        }
    }
}

private struct ScenesStoreFactoryKey: EnvironmentKey {
    static var defaultValue: ScenesStoreFactory {
        ScenesStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var scenesStoreFactory: ScenesStoreFactory {
        get { self[ScenesStoreFactoryKey.self] }
        set { self[ScenesStoreFactoryKey.self] = newValue }
    }
}
