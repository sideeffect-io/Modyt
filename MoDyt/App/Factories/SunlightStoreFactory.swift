import SwiftUI

struct SunlightStoreFactory {
    let make: @MainActor (String) -> SunlightStore

    static func live(environment: AppEnvironment) -> SunlightStoreFactory {
        SunlightStoreFactory { uniqueId in
            SunlightStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeSunlight: { uniqueId in
                        await environment.repository.observeDevice(uniqueId: uniqueId)
                    }
                )
            )
        }
    }
}

private struct SunlightStoreFactoryKey: EnvironmentKey {
    static var defaultValue: SunlightStoreFactory {
        SunlightStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var sunlightStoreFactory: SunlightStoreFactory {
        get { self[SunlightStoreFactoryKey.self] }
        set { self[SunlightStoreFactoryKey.self] = newValue }
    }
}
