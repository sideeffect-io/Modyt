import SwiftUI

struct EnergyConsumptionStoreFactory {
    let make: @MainActor (DeviceIdentifier) -> EnergyConsumptionStore

    static func live(dependencies: DependencyBag) -> EnergyConsumptionStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository

        return EnergyConsumptionStoreFactory { identifier in
            EnergyConsumptionStore(
                identifier: identifier,
                dependencies: .init(
                    observeEnergyConsumption: { await deviceRepository.observeByID($0) }
                )
            )
        }
    }
}

private struct EnergyConsumptionStoreFactoryKey: EnvironmentKey {
    static var defaultValue: EnergyConsumptionStoreFactory {
        EnergyConsumptionStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var energyConsumptionStoreFactory: EnergyConsumptionStoreFactory {
        get { self[EnergyConsumptionStoreFactoryKey.self] }
        set { self[EnergyConsumptionStoreFactoryKey.self] = newValue }
    }
}
