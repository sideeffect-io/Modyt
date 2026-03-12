import SwiftUI

extension SingleShutterStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("singleShutterStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var singleShutterStoreFactory: SingleShutterStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing SingleShutterView dependency: \(label)")
}
