import SwiftUI

struct SettingsStoreFactory {
    let make: @MainActor () -> SettingsStore

    static func live(environment: AppEnvironment) -> SettingsStoreFactory {
        SettingsStoreFactory {
            SettingsStore(
                dependencies: .init(
                    requestDisconnect: {
                        await environment.requestDisconnect()
                    }
                )
            )
        }
    }
}

private struct SettingsStoreFactoryKey: EnvironmentKey {
    static var defaultValue: SettingsStoreFactory { .live(environment: .live()) }
}

extension EnvironmentValues {
    var settingsStoreFactory: SettingsStoreFactory {
        get { self[SettingsStoreFactoryKey.self] }
        set { self[SettingsStoreFactoryKey.self] = newValue }
    }
}
