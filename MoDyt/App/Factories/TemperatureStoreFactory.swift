import SwiftUI

struct TemperatureStoreFactory {
    let make: @MainActor (String) -> TemperatureStore

    static func live(dependencies: DependencyBag) -> TemperatureStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository

        return TemperatureStoreFactory { uniqueId in
            TemperatureStore(
                dependencies: .init(
                    observeTemperature: { await deviceRepository.observeByID(uniqueId) }
                )
            )
        }
    }
}

private struct TemperatureStoreFactoryKey: EnvironmentKey {
    static var defaultValue: TemperatureStoreFactory {
        TemperatureStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var temperatureStoreFactory: TemperatureStoreFactory {
        get { self[TemperatureStoreFactoryKey.self] }
        set { self[TemperatureStoreFactoryKey.self] = newValue }
    }
}
