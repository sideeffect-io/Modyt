import SwiftUI

@main
struct MoDytApp: App {
    let environment = AppEnvironment.live()

    private let dependencyBag = DependencyBag.live()
    private let appCoordinatorStoreFactory: AppRootStoreFactory
    private let authenticationStoreFactory: AuthenticationStoreFactory
    private let mainStoreFactory: MainStoreFactory
    private let devicesStoreFactory: DevicesStoreFactory
    private let scenesStoreFactory: ScenesStoreFactory
    private let groupsStoreFactory: GroupsStoreFactory
    private let settingsStoreFactory: SettingsStoreFactory
    
    private let dashboardStoreFactory: DashboardStoreFactory
    private let dashboardDeviceCardStoreFactory: DashboardDeviceCardStoreFactory
    private let sceneExecutionStoreFactory: SceneExecutionStoreFactory
    private let shutterStoreFactory: ShutterStoreFactory
    private let lightStoreFactory: LightStoreFactory
    private let smokeStoreFactory: SmokeStoreFactory
    private let sunlightStoreFactory: SunlightStoreFactory
    private let energyConsumptionStoreFactory: EnergyConsumptionStoreFactory
    private let temperatureStoreFactory: TemperatureStoreFactory
    private let heatPumpStoreFactory: HeatPumpStoreFactory
    private let thermostatStoreFactory: ThermostatStoreFactory


    init() {
        appCoordinatorStoreFactory = .live
        authenticationStoreFactory = .live(dependencies: dependencyBag)
        mainStoreFactory = .live(dependencies: dependencyBag)
        devicesStoreFactory = .live(dependencies: dependencyBag)
        scenesStoreFactory = .live(dependencies: dependencyBag)
        groupsStoreFactory = .live(dependencies: dependencyBag)
        settingsStoreFactory = .live(dependencies: dependencyBag)
        
        
        
        dashboardStoreFactory = .live(dependencies: dependencyBag)
        dashboardDeviceCardStoreFactory = .live(dependencies: dependencyBag)
        sceneExecutionStoreFactory = .live(environment: environment)
        shutterStoreFactory = .live(environment: environment)
        lightStoreFactory = .live(environment: environment)
        smokeStoreFactory = .live(environment: environment)
        sunlightStoreFactory = .live(environment: environment)
        energyConsumptionStoreFactory = .live(environment: environment)
        temperatureStoreFactory = .live(environment: environment)
        heatPumpStoreFactory = .live(environment: environment)
        thermostatStoreFactory = .live(environment: environment)

    }

    var body: some SwiftUI.Scene {
        WindowGroup {
            AppRootView()
                .environment(\.appCoordinatorStoreFactory, appCoordinatorStoreFactory)
                .environment(\.authenticationStoreFactory, authenticationStoreFactory)
                .environment(\.mainStoreFactory, mainStoreFactory)
                .environment(\.dashboardStoreFactory, dashboardStoreFactory)
                .environment(\.dashboardDeviceCardStoreFactory, dashboardDeviceCardStoreFactory)
                .environment(\.sceneExecutionStoreFactory, sceneExecutionStoreFactory)
                .environment(\.shutterStoreFactory, shutterStoreFactory)
                .environment(\.lightStoreFactory, lightStoreFactory)
                .environment(\.smokeStoreFactory, smokeStoreFactory)
                .environment(\.sunlightStoreFactory, sunlightStoreFactory)
                .environment(\.energyConsumptionStoreFactory, energyConsumptionStoreFactory)
                .environment(\.temperatureStoreFactory, temperatureStoreFactory)
                .environment(\.heatPumpStoreFactory, heatPumpStoreFactory)
                .environment(\.thermostatStoreFactory, thermostatStoreFactory)
                .environment(\.devicesStoreFactory, devicesStoreFactory)
                .environment(\.scenesStoreFactory, scenesStoreFactory)
                .environment(\.groupsStoreFactory, groupsStoreFactory)
                .environment(\.settingsStoreFactory, settingsStoreFactory)
        }
    }
}
