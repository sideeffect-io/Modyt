import SwiftUI

struct AppRootStoreFactory {
    let make: @MainActor () -> AppRootStore

    static var live: AppRootStoreFactory {
        AppRootStoreFactory {
            AppRootStore()
        }
    }
}

private struct AppCoordinatorStoreFactoryKey: EnvironmentKey {
    static var defaultValue: AppRootStoreFactory { .live }
}

extension EnvironmentValues {
    var appCoordinatorStoreFactory: AppRootStoreFactory {
        get { self[AppCoordinatorStoreFactoryKey.self] }
        set { self[AppCoordinatorStoreFactoryKey.self] = newValue }
    }
}
