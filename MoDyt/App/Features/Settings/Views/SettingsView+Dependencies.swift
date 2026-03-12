import SwiftUI

extension SettingsStoreFactory {
    static let unimplemented = Self {
        missingDependency("settingsStoreFactory")
    }
}

extension EnvironmentValues {
    @Entry var settingsStoreFactory: SettingsStoreFactory = .unimplemented
}

private func missingDependency(_ label: StaticString) -> Never {
    fatalError("Missing SettingsView dependency: \(label)")
}
