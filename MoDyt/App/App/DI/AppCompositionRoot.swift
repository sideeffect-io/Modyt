import SwiftUI

struct AppCompositionRoot: Sendable {
    let mainStoreFactory: MainStoreFactory
    let devicesStoreFactory: DevicesStoreFactory
    let authenticationStoreFactory: AuthenticationStoreFactory
    let dashboardStoreFactory: DashboardStoreFactory
    let scenesStoreFactory: ScenesStoreFactory
    let dashboardDeviceCardStoreFactory: DashboardDeviceCardStoreFactory
    let sunlightStoreFactory: SunlightStoreFactory
    let sceneExecutionStoreFactory: SceneExecutionStoreFactory
    let settingsStoreFactory: SettingsStoreFactory
    let singleShutterStoreFactory: SingleShutterStoreFactory
    let groupShutterStoreFactory: GroupShutterStoreFactory
    let heatPumpStoreFactory: HeatPumpStoreFactory
    let energyConsumptionStoreFactory: EnergyConsumptionStoreFactory
    let thermostatStoreFactory: ThermostatStoreFactory
    let groupsStoreFactory: GroupsStoreFactory
    let temperatureStoreFactory: TemperatureStoreFactory
    let singleLightStoreFactory: SingleLightStoreFactory
    let groupLightStoreFactory: GroupLightStoreFactory
    let smokeStoreFactory: SmokeStoreFactory

    private init(
        mainStoreFactory: MainStoreFactory,
        devicesStoreFactory: DevicesStoreFactory,
        authenticationStoreFactory: AuthenticationStoreFactory,
        dashboardStoreFactory: DashboardStoreFactory,
        scenesStoreFactory: ScenesStoreFactory,
        dashboardDeviceCardStoreFactory: DashboardDeviceCardStoreFactory,
        sunlightStoreFactory: SunlightStoreFactory,
        sceneExecutionStoreFactory: SceneExecutionStoreFactory,
        settingsStoreFactory: SettingsStoreFactory,
        singleShutterStoreFactory: SingleShutterStoreFactory,
        groupShutterStoreFactory: GroupShutterStoreFactory,
        heatPumpStoreFactory: HeatPumpStoreFactory,
        energyConsumptionStoreFactory: EnergyConsumptionStoreFactory,
        thermostatStoreFactory: ThermostatStoreFactory,
        groupsStoreFactory: GroupsStoreFactory,
        temperatureStoreFactory: TemperatureStoreFactory,
        singleLightStoreFactory: SingleLightStoreFactory,
        groupLightStoreFactory: GroupLightStoreFactory,
        smokeStoreFactory: SmokeStoreFactory
    ) {
        self.mainStoreFactory = mainStoreFactory
        self.devicesStoreFactory = devicesStoreFactory
        self.authenticationStoreFactory = authenticationStoreFactory
        self.dashboardStoreFactory = dashboardStoreFactory
        self.scenesStoreFactory = scenesStoreFactory
        self.dashboardDeviceCardStoreFactory = dashboardDeviceCardStoreFactory
        self.sunlightStoreFactory = sunlightStoreFactory
        self.sceneExecutionStoreFactory = sceneExecutionStoreFactory
        self.settingsStoreFactory = settingsStoreFactory
        self.singleShutterStoreFactory = singleShutterStoreFactory
        self.groupShutterStoreFactory = groupShutterStoreFactory
        self.heatPumpStoreFactory = heatPumpStoreFactory
        self.energyConsumptionStoreFactory = energyConsumptionStoreFactory
        self.thermostatStoreFactory = thermostatStoreFactory
        self.groupsStoreFactory = groupsStoreFactory
        self.temperatureStoreFactory = temperatureStoreFactory
        self.singleLightStoreFactory = singleLightStoreFactory
        self.groupLightStoreFactory = groupLightStoreFactory
        self.smokeStoreFactory = smokeStoreFactory
    }

    init(dependencyBag: DependencyBag) {
        self.mainStoreFactory = MainStoreFactory.live(dependencyBag: dependencyBag)
        self.devicesStoreFactory = DevicesStoreFactory.live(dependencyBag: dependencyBag)
        self.authenticationStoreFactory = AuthenticationStoreFactory.live(dependencyBag: dependencyBag)
        self.dashboardStoreFactory = DashboardStoreFactory.live(dependencyBag: dependencyBag)
        self.scenesStoreFactory = ScenesStoreFactory.live(dependencyBag: dependencyBag)
        self.dashboardDeviceCardStoreFactory = DashboardDeviceCardStoreFactory.live(dependencyBag: dependencyBag)
        self.sunlightStoreFactory = SunlightStoreFactory.live(dependencyBag: dependencyBag)
        self.sceneExecutionStoreFactory = SceneExecutionStoreFactory.live(dependencyBag: dependencyBag)
        self.settingsStoreFactory = SettingsStoreFactory.live(dependencyBag: dependencyBag)
        self.singleShutterStoreFactory = SingleShutterStoreFactory.live(dependencyBag: dependencyBag)
        self.groupShutterStoreFactory = GroupShutterStoreFactory.live(dependencyBag: dependencyBag)
        self.heatPumpStoreFactory = HeatPumpStoreFactory.live(dependencyBag: dependencyBag)
        self.energyConsumptionStoreFactory = EnergyConsumptionStoreFactory.live(dependencyBag: dependencyBag)
        self.thermostatStoreFactory = ThermostatStoreFactory.live(dependencyBag: dependencyBag)
        self.groupsStoreFactory = GroupsStoreFactory.live(dependencyBag: dependencyBag)
        self.temperatureStoreFactory = TemperatureStoreFactory.live(dependencyBag: dependencyBag)
        self.singleLightStoreFactory = SingleLightStoreFactory.live(dependencyBag: dependencyBag)
        self.groupLightStoreFactory = GroupLightStoreFactory.live(dependencyBag: dependencyBag)
        self.smokeStoreFactory = SmokeStoreFactory.live(dependencyBag: dependencyBag)
    }

    static func live(
        dependencyBag: DependencyBag = .live()
    ) -> AppCompositionRoot {
        AppCompositionRoot(dependencyBag: dependencyBag)
    }
}

extension View {
    func appCompositionRoot(_ compositionRoot: AppCompositionRoot) -> some View {
        self
            .environment(\.mainStoreFactory, compositionRoot.mainStoreFactory)
            .environment(\.devicesStoreFactory, compositionRoot.devicesStoreFactory)
            .environment(\.authenticationStoreFactory, compositionRoot.authenticationStoreFactory)
            .environment(\.dashboardStoreFactory, compositionRoot.dashboardStoreFactory)
            .environment(\.scenesStoreFactory, compositionRoot.scenesStoreFactory)
            .environment(\.dashboardDeviceCardStoreFactory, compositionRoot.dashboardDeviceCardStoreFactory)
            .environment(\.sunlightStoreFactory, compositionRoot.sunlightStoreFactory)
            .environment(\.sceneExecutionStoreFactory, compositionRoot.sceneExecutionStoreFactory)
            .environment(\.settingsStoreFactory, compositionRoot.settingsStoreFactory)
            .environment(\.singleShutterStoreFactory, compositionRoot.singleShutterStoreFactory)
            .environment(\.groupShutterStoreFactory, compositionRoot.groupShutterStoreFactory)
            .environment(\.heatPumpStoreFactory, compositionRoot.heatPumpStoreFactory)
            .environment(\.energyConsumptionStoreFactory, compositionRoot.energyConsumptionStoreFactory)
            .environment(\.thermostatStoreFactory, compositionRoot.thermostatStoreFactory)
            .environment(\.groupsStoreFactory, compositionRoot.groupsStoreFactory)
            .environment(\.temperatureStoreFactory, compositionRoot.temperatureStoreFactory)
            .environment(\.singleLightStoreFactory, compositionRoot.singleLightStoreFactory)
            .environment(\.groupLightStoreFactory, compositionRoot.groupLightStoreFactory)
            .environment(\.smokeStoreFactory, compositionRoot.smokeStoreFactory)
    }
}
