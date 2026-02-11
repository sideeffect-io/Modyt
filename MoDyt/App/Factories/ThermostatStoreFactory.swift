import SwiftUI

struct ThermostatStoreFactory {
    let make: @MainActor (String) -> ThermostatStore

    static func live(environment: AppEnvironment) -> ThermostatStoreFactory {
        ThermostatStoreFactory { uniqueId in
            ThermostatStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeThermostat: { uniqueId in
                        await environment.repository.observeDevice(uniqueId: uniqueId)
                    }
                )
            )
        }
    }
}

private struct ThermostatStoreFactoryKey: EnvironmentKey {
    static var defaultValue: ThermostatStoreFactory {
        ThermostatStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var thermostatStoreFactory: ThermostatStoreFactory {
        get { self[ThermostatStoreFactoryKey.self] }
        set { self[ThermostatStoreFactoryKey.self] = newValue }
    }
}
