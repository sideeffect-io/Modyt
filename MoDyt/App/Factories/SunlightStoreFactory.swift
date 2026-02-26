import SwiftUI

struct SunlightStoreFactory {
    let make: @MainActor (String) -> SunlightStore

    static func live(dependencies: DependencyBag) -> SunlightStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository

        return SunlightStoreFactory { uniqueId in
            SunlightStore(
                dependencies: .init(
                    observeSunlight: { await deviceRepository.observeByID(uniqueId) }
                )
            )
        }
    }
}

private struct SunlightStoreFactoryKey: EnvironmentKey {
    static var defaultValue: SunlightStoreFactory {
        SunlightStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var sunlightStoreFactory: SunlightStoreFactory {
        get { self[SunlightStoreFactoryKey.self] }
        set { self[SunlightStoreFactoryKey.self] = newValue }
    }
}
