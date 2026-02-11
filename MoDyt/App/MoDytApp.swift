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
    private let sunlightStoreFactory: SunlightStoreFactory
    private let energyConsumptionStoreFactory: EnergyConsumptionStoreFactory
    private let temperatureStoreFactory: TemperatureStoreFactory
    private let heatPumpStoreFactory: HeatPumpStoreFactory
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
        sunlightStoreFactory = .live(environment: environment)
        energyConsumptionStoreFactory = .live(environment: environment)
        temperatureStoreFactory = .live(environment: environment)
        heatPumpStoreFactory = .live(environment: environment)
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
                .environment(\.sunlightStoreFactory, sunlightStoreFactory)
                .environment(\.energyConsumptionStoreFactory, energyConsumptionStoreFactory)
                .environment(\.temperatureStoreFactory, temperatureStoreFactory)
                .environment(\.heatPumpStoreFactory, heatPumpStoreFactory)
                .environment(\.thermostatStoreFactory, thermostatStoreFactory)
                .environment(\.devicesStoreFactory, devicesStoreFactory)
                .environment(\.settingsStoreFactory, settingsStoreFactory)
        }
    }
}
