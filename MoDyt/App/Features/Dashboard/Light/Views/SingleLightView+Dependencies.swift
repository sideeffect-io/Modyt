import SwiftUI

extension SingleLightStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("singleLightStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var singleLightStoreFactory: SingleLightStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing SingleLightView dependency: \(label)")
}
