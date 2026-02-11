import SwiftUI

struct HeatPumpStoreFactory {
    let make: @MainActor (String) -> HeatPumpStore

    static func live(environment: AppEnvironment) -> HeatPumpStoreFactory {
        HeatPumpStoreFactory { uniqueId in
            HeatPumpStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeHeatPump: { uniqueId in
                        await environment.repository.observeDevice(uniqueId: uniqueId)
                    },
                    applyOptimisticChanges: { uniqueId, changes in
                        await environment.repository.applyOptimisticUpdates(uniqueId: uniqueId, changes: changes)
                    },
                    sendCommand: { uniqueId, key, value in
                        await environment.sendDeviceCommand(uniqueId, key, value)
                    },
                    now: environment.now
                )
            )
        }
    }
}

private struct HeatPumpStoreFactoryKey: EnvironmentKey {
    static var defaultValue: HeatPumpStoreFactory {
        HeatPumpStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var heatPumpStoreFactory: HeatPumpStoreFactory {
        get { self[HeatPumpStoreFactoryKey.self] }
        set { self[HeatPumpStoreFactoryKey.self] = newValue }
    }
}
