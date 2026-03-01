import SwiftUI

struct SmokeStoreFactory {
    let make: @MainActor (DeviceIdentifier) -> SmokeStore

    static func live(dependencies: DependencyBag) -> SmokeStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository

        return SmokeStoreFactory { identifier in
            SmokeStore(
                identifier: identifier,
                dependencies: .init(
                    observeSmoke: { await deviceRepository.observeByID($0).removeDuplicates() }
                )
            )
        }
    }
}

private struct SmokeStoreFactoryKey: EnvironmentKey {
    static var defaultValue: SmokeStoreFactory {
        SmokeStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var smokeStoreFactory: SmokeStoreFactory {
        get { self[SmokeStoreFactoryKey.self] }
        set { self[SmokeStoreFactoryKey.self] = newValue }
    }
}
