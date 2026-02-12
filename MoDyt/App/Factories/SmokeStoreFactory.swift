import SwiftUI

struct SmokeStoreFactory {
    let make: @MainActor (String) -> SmokeStore

    static func live(environment: AppEnvironment) -> SmokeStoreFactory {
        SmokeStoreFactory { uniqueId in
            SmokeStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeSmoke: { uniqueId in
                        await environment.repository.observeDevice(uniqueId: uniqueId)
                    }
                )
            )
        }
    }
}

private struct SmokeStoreFactoryKey: EnvironmentKey {
    static var defaultValue: SmokeStoreFactory {
        SmokeStoreFactory.live(environment: .live())
    }
}

extension EnvironmentValues {
    var smokeStoreFactory: SmokeStoreFactory {
        get { self[SmokeStoreFactoryKey.self] }
        set { self[SmokeStoreFactoryKey.self] = newValue }
    }
}
