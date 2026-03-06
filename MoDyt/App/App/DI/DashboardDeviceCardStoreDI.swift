import SwiftUI

enum DashboardDeviceCardStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> DashboardDeviceCardStore.Dependencies {
        let favoritesRepository = dependencyBag.localStorageDatasources.favoritesRepository

        return .init(
            toggleFavorite: { favoriteType in
                try? await favoritesRepository.toggleFavorite(favoriteType)
            }
        )
    }
}

extension EnvironmentValues {
    @Entry var dashboardDeviceCardStoreDependencies: DashboardDeviceCardStore.Dependencies =
        DashboardDeviceCardStoreDependencyFactory.make()
}
