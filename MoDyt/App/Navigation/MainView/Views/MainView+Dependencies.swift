import SwiftUI

extension MainStoreFactory {
    static let unimplemented = Self {
        missingDependency("mainStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var mainStoreFactory: MainStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing MainView dependency: \(label)")
}
