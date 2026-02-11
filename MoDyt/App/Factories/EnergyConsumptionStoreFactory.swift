import SwiftUI

struct EnergyConsumptionStoreFactory {
    let make: @MainActor (String) -> EnergyConsumptionStore

    static func live(environment: AppEnvironment) -> EnergyConsumptionStoreFactory {
        EnergyConsumptionStoreFactory { uniqueId in
            EnergyConsumptionStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeEnergyConsumption: { uniqueId in
                        await environment.repository.observeDevice(uniqueId: uniqueId)
                    }
                )
            )
        }
    }
}

private struct EnergyConsumptionStoreFactoryKey: EnvironmentKey {
    static var defaultValue: EnergyConsumptionStoreFactory {
        EnergyConsumptionStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var energyConsumptionStoreFactory: EnergyConsumptionStoreFactory {
        get { self[EnergyConsumptionStoreFactoryKey.self] }
        set { self[EnergyConsumptionStoreFactoryKey.self] = newValue }
    }
}
