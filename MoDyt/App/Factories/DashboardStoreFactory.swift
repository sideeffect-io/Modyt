import SwiftUI

struct DashboardStoreFactory {
    let make: @MainActor () -> DashboardStore

    static func live(environment: AppEnvironment) -> DashboardStoreFactory {
        DashboardStoreFactory {
            DashboardStore(
                dependencies: .init(
                    observeFavoriteDevices: {
                        await environment.repository.observeFavorites()
                    },
                    toggleFavorite: { uniqueId in
                        await environment.repository.toggleFavorite(uniqueId: uniqueId)
                    },
                    reorderFavorite: { sourceId, targetId in
                        await environment.repository.reorderDashboard(from: sourceId, to: targetId)
                    },
                    refreshAll: {
                        await environment.requestRefreshAll()
                    }
                )
            )
        }
    }
}

private struct DashboardStoreFactoryKey: EnvironmentKey {
    static var defaultValue: DashboardStoreFactory {
        DashboardStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var dashboardStoreFactory: DashboardStoreFactory {
        get { self[DashboardStoreFactoryKey.self] }
        set { self[DashboardStoreFactoryKey.self] = newValue }
    }
}
