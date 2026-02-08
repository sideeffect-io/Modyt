import SwiftUI

struct DevicesStoreFactory {
    let make: @MainActor () -> DevicesStore

    static func live(environment: AppEnvironment) -> DevicesStoreFactory {
        DevicesStoreFactory {
            DevicesStore(
                dependencies: .init(
                    observeDevices: {
                        await environment.repository.observeDevices()
                    },
                    toggleFavorite: { uniqueId in
                        await environment.repository.toggleFavorite(uniqueId: uniqueId)
                    },
                    refreshAll: {
                        await environment.requestRefreshAll()
                    }
                )
            )
        }
    }
}

private struct DevicesStoreFactoryKey: EnvironmentKey {
    static var defaultValue: DevicesStoreFactory {
        DevicesStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var devicesStoreFactory: DevicesStoreFactory {
        get { self[DevicesStoreFactoryKey.self] }
        set { self[DevicesStoreFactoryKey.self] = newValue }
    }
}
