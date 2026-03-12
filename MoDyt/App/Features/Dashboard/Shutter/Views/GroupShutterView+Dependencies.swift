import SwiftUI

extension GroupShutterStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("groupShutterStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var groupShutterStoreFactory: GroupShutterStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing GroupShutterView dependency: \(label)")
}
