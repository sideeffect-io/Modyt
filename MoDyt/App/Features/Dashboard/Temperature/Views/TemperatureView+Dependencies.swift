import SwiftUI

extension TemperatureStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("temperatureStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var temperatureStoreFactory: TemperatureStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing TemperatureView dependency: \(label)")
}
