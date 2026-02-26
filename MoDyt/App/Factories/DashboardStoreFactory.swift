import SwiftUI
import DeltaDoreClient

struct DashboardStoreFactory {
    let make: @MainActor () -> DashboardStore

    static func live(dependencies: DependencyBag) -> DashboardStoreFactory {
        let favoritesRepository = dependencies.localStorageDatasources.favoritesRepository
        let gatewayClient = dependencies.gatewayClient

        return DashboardStoreFactory {
            DashboardStore(
                dependencies: .init(
                    observeFavorites: { await favoritesRepository.observeAll() },
                    reorderFavorite: { source, target in try? await favoritesRepository.reorder(source, target) },
                    refreshAll: { try? await gatewayClient.send(text: TydomCommand.refreshAll().request) }
                )
            )
        }
    }
}

private struct DashboardStoreFactoryKey: EnvironmentKey {
    static var defaultValue: DashboardStoreFactory {
        DashboardStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var dashboardStoreFactory: DashboardStoreFactory {
        get { self[DashboardStoreFactoryKey.self] }
        set { self[DashboardStoreFactoryKey.self] = newValue }
    }
}
