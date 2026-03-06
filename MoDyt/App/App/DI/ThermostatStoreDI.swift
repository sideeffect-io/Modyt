import SwiftUI

enum ThermostatStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> ThermostatStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return .init(
            observeThermostat: { await deviceRepository.observeByID($0).removeDuplicates() }
        )
    }
}

extension EnvironmentValues {
    @Entry var thermostatStoreDependencies: ThermostatStore.Dependencies =
        ThermostatStoreDependencyFactory.make()
}
