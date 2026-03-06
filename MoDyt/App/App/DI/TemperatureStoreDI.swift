import SwiftUI

enum TemperatureStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> TemperatureStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return .init(
            observeTemperature: { await deviceRepository.observeByID($0) }
        )
    }
}

extension EnvironmentValues {
    @Entry var temperatureStoreDependencies: TemperatureStore.Dependencies =
        TemperatureStoreDependencyFactory.make()
}
