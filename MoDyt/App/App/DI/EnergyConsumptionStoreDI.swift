import SwiftUI

enum EnergyConsumptionStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> EnergyConsumptionStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return .init(
            observeEnergyConsumption: { await deviceRepository.observeByID($0) }
        )
    }
}

extension EnvironmentValues {
    @Entry var energyConsumptionStoreDependencies: EnergyConsumptionStore.Dependencies =
        EnergyConsumptionStoreDependencyFactory.make()
}
