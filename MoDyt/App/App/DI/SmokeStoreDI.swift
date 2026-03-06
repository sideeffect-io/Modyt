import SwiftUI

enum SmokeStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> SmokeStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository

        return .init(
            observeSmoke: { await deviceRepository.observeByID($0).removeDuplicates() }
        )
    }
}

extension EnvironmentValues {
    @Entry var smokeStoreDependencies: SmokeStore.Dependencies =
        SmokeStoreDependencyFactory.make()
}
