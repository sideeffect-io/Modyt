import SwiftUI

struct DashboardDeviceCardStoreFactory {
    let make: @MainActor (FavoriteType) -> DashboardDeviceCardStore

    static func live(dependencies: DependencyBag) -> DashboardDeviceCardStoreFactory {
        let favoritesRepository = dependencies.localStorageDatasources.favoritesRepository

        return DashboardDeviceCardStoreFactory { favoriteType in
            DashboardDeviceCardStore(
                favoriteType: favoriteType,
                dependencies: .init(
                    toggleFavorite: { favoriteType in try? await favoritesRepository.toggleFavorite(favoriteType) }
                )
            )
        }
    }
}

private struct DashboardDeviceCardStoreFactoryKey: EnvironmentKey {
    static var defaultValue: DashboardDeviceCardStoreFactory {
        DashboardDeviceCardStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var dashboardDeviceCardStoreFactory: DashboardDeviceCardStoreFactory {
        get { self[DashboardDeviceCardStoreFactoryKey.self] }
        set { self[DashboardDeviceCardStoreFactoryKey.self] = newValue }
    }
}
