import SwiftUI

extension SunlightStoreFactory {
    static let unimplemented = Self { _ in
        missingDependency("sunlightStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var sunlightStoreFactory: SunlightStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing SunlightView dependency: \(label)")
}
