import SwiftUI

extension DevicesStoreFactory {
    static let unimplemented = Self {
        missingDependency("devicesStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var devicesStoreFactory: DevicesStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing DevicesView dependency: \(label)")
}
