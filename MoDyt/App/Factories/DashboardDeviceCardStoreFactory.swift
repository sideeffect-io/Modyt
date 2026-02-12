import SwiftUI
import DeltaDoreClient

struct DashboardDeviceCardStoreFactory {
    let make: @MainActor (String) -> DashboardDeviceCardStore

    static func live(environment: AppEnvironment) -> DashboardDeviceCardStoreFactory {
        DashboardDeviceCardStoreFactory { uniqueId in
            DashboardDeviceCardStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    toggleFavorite: { uniqueId in
                        if SceneRecord.isSceneUniqueId(uniqueId) {
                            await environment.sceneRepository.toggleFavorite(uniqueId: uniqueId)
                        } else {
                            await environment.repository.toggleFavorite(uniqueId: uniqueId)
                        }
                    }
                )
            )
        }
    }
}

private struct DashboardDeviceCardStoreFactoryKey: EnvironmentKey {
    static var defaultValue: DashboardDeviceCardStoreFactory {
        DashboardDeviceCardStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var dashboardDeviceCardStoreFactory: DashboardDeviceCardStoreFactory {
        get { self[DashboardDeviceCardStoreFactoryKey.self] }
        set { self[DashboardDeviceCardStoreFactoryKey.self] = newValue }
    }
}
