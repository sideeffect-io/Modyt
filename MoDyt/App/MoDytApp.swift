import SwiftUI

@main
struct MoDytApp: App {
    private let appCoordinatorStoreFactory: AppRootStoreFactory
    private let authenticationStoreFactory: AuthenticationStoreFactory
    private let rootTabStoreFactory: RootTabStoreFactory
    private let dashboardStoreFactory: DashboardStoreFactory
    private let dashboardDeviceCardStoreFactory: DashboardDeviceCardStoreFactory
    private let shutterStoreFactory: ShutterStoreFactory
    private let lightStoreFactory: LightStoreFactory
    private let temperatureStoreFactory: TemperatureStoreFactory
    private let thermostatStoreFactory: ThermostatStoreFactory
    private let devicesStoreFactory: DevicesStoreFactory
    private let settingsStoreFactory: SettingsStoreFactory

    init() {
        let environment = AppEnvironment.live()
        appCoordinatorStoreFactory = .live
        authenticationStoreFactory = .live(environment: environment)
        rootTabStoreFactory = .live(environment: environment)
        dashboardStoreFactory = .live(environment: environment)
        dashboardDeviceCardStoreFactory = .live(environment: environment)
        shutterStoreFactory = .live(environment: environment)
        lightStoreFactory = .live(environment: environment)
        temperatureStoreFactory = .live(environment: environment)
        thermostatStoreFactory = .live(environment: environment)
        devicesStoreFactory = .live(environment: environment)
        settingsStoreFactory = .live(environment: environment)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .environment(\.appCoordinatorStoreFactory, appCoordinatorStoreFactory)
                .environment(\.authenticationStoreFactory, authenticationStoreFactory)
                .environment(\.rootTabStoreFactory, rootTabStoreFactory)
                .environment(\.dashboardStoreFactory, dashboardStoreFactory)
                .environment(\.dashboardDeviceCardStoreFactory, dashboardDeviceCardStoreFactory)
                .environment(\.shutterStoreFactory, shutterStoreFactory)
                .environment(\.lightStoreFactory, lightStoreFactory)
                .environment(\.temperatureStoreFactory, temperatureStoreFactory)
                .environment(\.thermostatStoreFactory, thermostatStoreFactory)
                .environment(\.devicesStoreFactory, devicesStoreFactory)
                .environment(\.settingsStoreFactory, settingsStoreFactory)
        }
    }
}
