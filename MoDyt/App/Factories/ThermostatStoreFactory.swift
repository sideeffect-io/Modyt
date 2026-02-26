import SwiftUI

struct ThermostatStoreFactory {
    let make: @MainActor (String) -> ThermostatStore

    static func live(dependencies: DependencyBag) -> ThermostatStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository

        return ThermostatStoreFactory { uniqueId in
            ThermostatStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeThermostat: { await deviceRepository.observeByID($0).removeDuplicates() }
                )
            )
        }
    }
}

private struct ThermostatStoreFactoryKey: EnvironmentKey {
    static var defaultValue: ThermostatStoreFactory {
        ThermostatStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var thermostatStoreFactory: ThermostatStoreFactory {
        get { self[ThermostatStoreFactoryKey.self] }
        set { self[ThermostatStoreFactoryKey.self] = newValue }
    }
}
