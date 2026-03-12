import SwiftUI

extension ThermostatStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("thermostatStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var thermostatStoreFactory: ThermostatStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing ThermostatView dependency: \(label)")
}
