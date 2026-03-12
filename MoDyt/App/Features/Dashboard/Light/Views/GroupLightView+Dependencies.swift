import SwiftUI

extension GroupLightStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("groupLightStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var groupLightStoreFactory: GroupLightStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing GroupLightView dependency: \(label)")
}
