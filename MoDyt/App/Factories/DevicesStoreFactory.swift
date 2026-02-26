import SwiftUI
import DeltaDoreClient

struct DevicesStoreFactory {
    let make: @MainActor () -> DevicesStore

    static func live(dependencies: DependencyBag) -> DevicesStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository
        let gatewayClient = dependencies.gatewayClient

        return DevicesStoreFactory {
            DevicesStore(
                dependencies: .init(
                    observeDevices: { await deviceRepository.observeGroupedByType() },
                    toggleFavorite: { deviceID in try? await deviceRepository.toggleFavorite(deviceID) },
                    refreshAll: { try? await gatewayClient.send(text: TydomCommand.refreshAll().request) }
                )
            )
        }
    }
}

private struct DevicesStoreFactoryKey: EnvironmentKey {
    static var defaultValue: DevicesStoreFactory {
        DevicesStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var devicesStoreFactory: DevicesStoreFactory {
        get { self[DevicesStoreFactoryKey.self] }
        set { self[DevicesStoreFactoryKey.self] = newValue }
    }
}
