import SwiftUI

extension SceneExecutionStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("sceneExecutionStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var sceneExecutionStoreFactory: SceneExecutionStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing SceneExecutionView dependency: \(label)")
}
