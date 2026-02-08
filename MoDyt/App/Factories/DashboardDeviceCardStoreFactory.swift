import SwiftUI
import DeltaDoreClient

struct DashboardDeviceCardStoreFactory {
    let make: @MainActor (String) -> DashboardDeviceCardStore

    static func live(environment: AppEnvironment) -> DashboardDeviceCardStoreFactory {
        DashboardDeviceCardStoreFactory { uniqueId in
            DashboardDeviceCardStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeDevice: { uniqueId in
                        await environment.repository.observeDevice(uniqueId: uniqueId)
                    },
                    applyOptimisticUpdate: { uniqueId, key, value in
                        await environment.repository.applyOptimisticUpdate(uniqueId: uniqueId, key: key, value: value)
                    },
                    sendDeviceCommand: { uniqueId, key, value in
                        await environment.sendDeviceCommand(uniqueId, key, value)
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
