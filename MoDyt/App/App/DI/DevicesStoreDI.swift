import SwiftUI
import DeltaDoreClient

enum DevicesStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> DevicesStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeDevices: { await deviceRepository.observeGroupedByType() },
            toggleFavorite: { deviceID in try? await deviceRepository.toggleFavorite(deviceID) },
            refreshAll: { try? await gatewayClient.send(text: TydomCommand.refreshAll().request) }
        )
    }
}

extension EnvironmentValues {
    @Entry var devicesStoreDependencies: DevicesStore.Dependencies =
        DevicesStoreDependencyFactory.make()
}
