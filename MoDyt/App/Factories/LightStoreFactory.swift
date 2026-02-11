import SwiftUI

struct LightStoreFactory {
    let make: @MainActor (String) -> LightStore

    static func live(environment: AppEnvironment) -> LightStoreFactory {
        LightStoreFactory { uniqueId in
            LightStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeLight: { uniqueId in
                        await environment.repository.observeDevice(uniqueId: uniqueId)
                    },
                    applyOptimisticChanges: { uniqueId, changes in
                        await environment.repository.applyOptimisticUpdates(uniqueId: uniqueId, changes: changes)
                    },
                    sendCommand: { uniqueId, key, value in
                        await environment.sendDeviceCommand(uniqueId, key, value)
                    }
                )
            )
        }
    }
}

private struct LightStoreFactoryKey: EnvironmentKey {
    static var defaultValue: LightStoreFactory {
        LightStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var lightStoreFactory: LightStoreFactory {
        get { self[LightStoreFactoryKey.self] }
        set { self[LightStoreFactoryKey.self] = newValue }
    }
}
