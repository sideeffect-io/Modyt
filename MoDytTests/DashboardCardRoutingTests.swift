import Foundation
import Testing
@testable import MoDyt

struct DashboardCardRoutingTests {
    @Test
    func singleShutterFavoritesRouteToSingleShutter() {
        let identifier = DeviceIdentifier(deviceId: 42, endpointId: 1)
        let favorite = FavoriteItem(
            name: "Bedroom shutter",
            usage: .shutter,
            type: .device(identifier: identifier),
            order: 0
        )

        #expect(DashboardShutterRoute(favorite: favorite) == .single(identifier))
    }

    @Test
    func groupShutterFavoritesRouteToGroupShutterWithUniqueIds() {
        let first = DeviceIdentifier(deviceId: 42, endpointId: 1)
        let second = DeviceIdentifier(deviceId: 43, endpointId: 1)
        let favorite = FavoriteItem(
            name: "All shutters",
            usage: .shutter,
            type: .group(groupId: "group-1", memberIdentifiers: [first, second, first]),
            order: 0
        )

        #expect(DashboardShutterRoute(favorite: favorite) == .group([first, second]))
    }

    @Test
    func emptyGroupShutterFavoritesRouteToUnavailable() {
        let favorite = FavoriteItem(
            name: "Empty group",
            usage: .shutter,
            type: .group(groupId: "group-1", memberIdentifiers: []),
            order: 0
        )

        #expect(DashboardShutterRoute(favorite: favorite) == .unavailable)
    }

    @Test
    func shHvacRoutesToHeatPumpControlKind() {
        let device = makeDevice(
            usage: "sh_hvac",
            data: [
                "regTemperature": .number(20.5),
                "currentSetpoint": .number(21.0)
            ]
        )

        #expect(device.controlKind == .heatPump)
    }

    @Test
    func boilerWithThermostatSignalsRoutesToThermostatControlKind() {
        let device = makeDevice(
            usage: "boiler",
            data: [
                "temperature": .number(19.4),
                "setpoint": .number(20.0),
                "authorization": .string("HEATING")
            ]
        )

        #expect(device.controlKind == .thermostat)
    }

    @Test
    func sensorThermoRoutesToTemperatureControlKind() {
        let device = makeDevice(
            usage: "sensorThermo",
            data: [
                "outTemperature": .number(11.2)
            ]
        )

        #expect(device.controlKind == .temperature)
    }

    @Test
    func sensorThermoWithHeatPumpSignalsRoutesToHeatPumpControlKind() {
        let device = makeDevice(
            usage: "sensorThermo",
            data: [
                "regTemperature": .number(21.8),
                "currentSetpoint": .number(22.0)
            ]
        )

        #expect(device.controlKind == .heatPump)
    }

    @Test
    func capabilityBasedRoutingBeatsNameHints() {
        let device = makeDevice(
            name: "Heat Pump Bedroom",
            usage: "boiler",
            data: [
                "temperature": .number(20.1),
                "setpoint": .number(21.0),
                "hvacMode": .string("NORMAL")
            ]
        )

        #expect(device.controlKind == .thermostat)
    }

    @Test
    func boilerWithHeatPumpSignalsRoutesToHeatPumpControlKind() {
        let device = makeDevice(
            usage: "boiler",
            data: [
                "regTemperature": .number(20.1),
                "currentSetpoint": .number(21.0),
                "waterFlowReq": .bool(true)
            ]
        )

        #expect(device.controlKind == .heatPump)
    }

    @Test
    func boilerWithBoostOnSignalRoutesToHeatPumpControlKind() {
        let device = makeDevice(
            usage: "boiler",
            data: [
                "temperature": .number(20.9),
                "setpoint": .number(20.0),
                "boostOn": .bool(false)
            ]
        )

        #expect(device.controlKind == .heatPump)
    }

    @Test
    func usageContainingHvacRoutesToHeatPumpControlKind() {
        let device = makeDevice(
            usage: "custom_hvac_controller",
            data: [
                "temperature": .number(20.2)
            ]
        )

        #expect(device.controlKind == .heatPump)
    }

    @Test
    func consoUsageWithOutTemperatureStillRoutesToEnergyConsumptionControlKind() {
        let device = makeDevice(
            usage: "conso",
            data: [
                "energyIndexHeatWatt": .number(782000),
                "energyIndexECSWatt": .number(366000),
                "energyIndexCoolWatt": .number(0),
                "outTemperature": .number(11.1)
            ]
        )

        #expect(device.controlKind == .energyConsumption)
    }

    private func makeDevice(
        name: String = "Device",
        usage: String,
        data: [String: JSONValue]
    ) -> Device {
        Device(
            id: .init(deviceId: 42, endpointId: 1),
            deviceId: 42,
            endpointId: 1,
            name: name,
            usage: usage,
            kind: "kind",
            data: data,
            metadata: nil,
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }
}
