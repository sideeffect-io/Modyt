import SwiftUI
import DeltaDoreClient

struct SettingsStoreFactory {
    let make: @MainActor () -> SettingsStore

    static func live(dependencies: DependencyBag) -> SettingsStoreFactory {
        SettingsStoreFactory {
            SettingsStore(
                dependencies: .init(
                    requestDisconnect: {
                        await dependencies.gatewayClient.disconnectCurrentConnection()
                        await dependencies.gatewayClient.clearStoredData()
                        await dependencies.localStorageDatasources.tydomMessageRepositoryRouter.clearRepositories()
                    }
                )
            )
        }
    }
}

private struct SettingsStoreFactoryKey: EnvironmentKey {
    static var defaultValue: SettingsStoreFactory { .live(dependencies: .live()) }
}

extension EnvironmentValues {
    var settingsStoreFactory: SettingsStoreFactory {
        get { self[SettingsStoreFactoryKey.self] }
        set { self[SettingsStoreFactoryKey.self] = newValue }
    }
}
