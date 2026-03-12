import SwiftUI

extension HeatPumpStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("heatPumpStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var heatPumpStoreFactory: HeatPumpStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing HeatPumpView dependency: \(label)")
}
