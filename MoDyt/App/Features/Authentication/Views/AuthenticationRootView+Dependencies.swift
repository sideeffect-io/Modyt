import SwiftUI

extension AuthenticationStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("authenticationStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var authenticationStoreFactory: AuthenticationStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing AuthenticationRootView dependency: \(label)")
}
