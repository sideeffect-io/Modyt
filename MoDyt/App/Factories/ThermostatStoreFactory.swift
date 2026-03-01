import SwiftUI

struct ThermostatStoreFactory {
    let make: @MainActor (DeviceIdentifier) -> ThermostatStore

    static func live(dependencies: DependencyBag) -> ThermostatStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository

        return ThermostatStoreFactory { identifier in
            ThermostatStore(
                identifier: identifier,
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
