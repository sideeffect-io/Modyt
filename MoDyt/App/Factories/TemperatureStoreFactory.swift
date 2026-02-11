import SwiftUI

struct TemperatureStoreFactory {
    let make: @MainActor (String) -> TemperatureStore

    static func live(environment: AppEnvironment) -> TemperatureStoreFactory {
        TemperatureStoreFactory { uniqueId in
            TemperatureStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeTemperature: { uniqueId in
                        await environment.repository.observeDevice(uniqueId: uniqueId)
                    }
                )
            )
        }
    }
}

private struct TemperatureStoreFactoryKey: EnvironmentKey {
    static var defaultValue: TemperatureStoreFactory {
        TemperatureStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var temperatureStoreFactory: TemperatureStoreFactory {
        get { self[TemperatureStoreFactoryKey.self] }
        set { self[TemperatureStoreFactoryKey.self] = newValue }
    }
}
