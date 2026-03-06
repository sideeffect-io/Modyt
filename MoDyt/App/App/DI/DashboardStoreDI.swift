import SwiftUI
import DeltaDoreClient

enum DashboardStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> DashboardStore.Dependencies {
        let favoritesRepository = dependencyBag.localStorageDatasources.favoritesRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeFavorites: { await favoritesRepository.observeAll() },
            reorderFavorite: { source, target in try? await favoritesRepository.reorder(source, target) },
            refreshAll: { try? await gatewayClient.send(text: TydomCommand.refreshAll().request) }
        )
    }
}

extension EnvironmentValues {
    @Entry var dashboardStoreDependencies: DashboardStore.Dependencies =
        DashboardStoreDependencyFactory.make()
}
