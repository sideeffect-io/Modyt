import SwiftUI

extension EnergyConsumptionStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("energyConsumptionStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var energyConsumptionStoreFactory: EnergyConsumptionStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing EnergyConsumptionView dependency: \(label)")
}
