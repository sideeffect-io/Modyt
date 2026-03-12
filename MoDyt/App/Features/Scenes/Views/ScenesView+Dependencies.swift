import SwiftUI

extension ScenesStoreFactory {
    static let unimplemented = Self {
        missingDependency("scenesStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var scenesStoreFactory: ScenesStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing ScenesView dependency: \(label)")
}
