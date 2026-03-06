import SwiftUI

enum SunlightStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> SunlightStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return .init(
            observeSunlight: { await deviceRepository.observeByID($0) }
        )
    }
}

extension EnvironmentValues {
    @Entry var sunlightStoreDependencies: SunlightStore.Dependencies =
        SunlightStoreDependencyFactory.make()
}
