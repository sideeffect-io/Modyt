import SwiftUI
import DeltaDoreClient

enum ScenesStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> ScenesStore.Dependencies {
        let sceneRepository = dependencyBag.localStorageDatasources.sceneRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeScenes: { await sceneRepository.observeAll() },
            toggleFavorite: { sceneID in try? await sceneRepository.toggleFavorite(sceneID) },
            refreshAll: { try? await gatewayClient.send(text: TydomCommand.refreshAll().request) }
        )
    }
}

extension EnvironmentValues {
    @Entry var scenesStoreDependencies: ScenesStore.Dependencies =
        ScenesStoreDependencyFactory.make()
}
