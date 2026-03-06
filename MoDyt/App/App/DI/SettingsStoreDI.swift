import SwiftUI
import DeltaDoreClient

enum SettingsStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> SettingsStore.Dependencies {
        let gatewayClient = dependencyBag.gatewayClient
        let messageRouter = dependencyBag.localStorageDatasources.tydomMessageRepositoryRouter

        return .init(
            requestDisconnect: {
                await gatewayClient.disconnectCurrentConnection()
                await gatewayClient.clearStoredData()
                await messageRouter.clearRepositories()
            }
        )
    }
}

extension EnvironmentValues {
    @Entry var settingsStoreDependencies: SettingsStore.Dependencies =
        SettingsStoreDependencyFactory.make()
}
