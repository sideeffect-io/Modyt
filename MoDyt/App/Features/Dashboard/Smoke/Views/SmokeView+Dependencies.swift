import SwiftUI

extension SmokeStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("smokeStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var smokeStoreFactory: SmokeStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing SmokeView dependency: \(label)")
}
