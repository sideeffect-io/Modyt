import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct DeviceRecordTests {
    @Test
    func drivingLightControlDescriptorUsesPowerAndLevelKeys() {
        let device = TestSupport.makeDevice(
            uniqueId: "light-1",
            name: "Driveway",
            usage: "light",
            data: ["on": .bool(true), "level": .number(50)],
            metadata: ["level": .object(["min": .number(0), "max": .number(200)])]
        )

        let descriptor = device.drivingLightControlDescriptor()

        #expect(descriptor?.powerKey == "on")
        #expect(descriptor?.levelKey == "level")
        #expect(descriptor?.isOn == true)
        #expect(descriptor?.level == 50)
        #expect(descriptor?.percentage == 25)
    }

    @Test
    func drivingLightControlDescriptorFallsBackToStateWhenLevelIsMissing() {
        let device = TestSupport.makeDevice(
            uniqueId: "light-2",
            name: "Garage",
            usage: "light",
            data: ["state": .bool(false)]
        )

        let descriptor = device.drivingLightControlDescriptor()

        #expect(descriptor?.powerKey == "state")
        #expect(descriptor?.levelKey == nil)
        #expect(descriptor?.isOn == false)
        #expect(descriptor?.level == 0)
        #expect(descriptor?.percentage == 0)
    }

    @Test
    func drivingLightControlDescriptorFallsBackToLevelWhenPowerIsMissing() {
        let device = TestSupport.makeDevice(
            uniqueId: "light-3",
            name: "Porch",
            usage: "light",
            data: ["level": .number(35)],
            metadata: ["level": .object(["min": .number(0), "max": .number(70)])]
        )

        let descriptor = device.drivingLightControlDescriptor()

        #expect(descriptor?.powerKey == nil)
        #expect(descriptor?.levelKey == "level")
        #expect(descriptor?.isOn == true)
        #expect(descriptor?.percentage == 50)
    }

    @Test
    func drivingLightControlDescriptorIsNilForNonLightDevices() {
        let device = TestSupport.makeDevice(
            uniqueId: "shutter-1",
            name: "Living Room",
            usage: "shutter",
            data: ["level": .number(40)]
        )

        #expect(device.drivingLightControlDescriptor() == nil)
    }

    @Test
    func temperatureDescriptorUsesPreferredKeyAndNormalizesUnit() {
        let device = TestSupport.makeDevice(
            uniqueId: "thermo-1",
            name: "Outdoor Sensor",
            usage: "sensorThermo",
            data: [
                "battery": .number(92),
                "temperature": .number(18.4)
            ],
            metadata: [
                "temperature": .object(["unit": .string("celsius")])
            ]
        )

        let descriptor = device.temperatureDescriptor()

        #expect(descriptor?.key == "temperature")
        #expect(descriptor?.value == 18.4)
        #expect(descriptor?.unitSymbol == "°C")
    }

    @Test
    func temperatureDescriptorPrefersOutTemperatureOverConfigValue() {
        let device = TestSupport.makeDevice(
            uniqueId: "thermo-2",
            name: "Outdoor Probe",
            usage: "sensorThermo",
            data: [
                "configTemp": .number(520),
                "outTemperature": .number(11.0)
            ],
            metadata: [
                "configTemp": .object(["unit": .string("NA")]),
                "outTemperature": .object(["unit": .string("degC")])
            ]
        )

        let descriptor = device.temperatureDescriptor()

        #expect(descriptor?.key == "outTemperature")
        #expect(descriptor?.value == 11.0)
        #expect(descriptor?.unitSymbol == "°C")
    }

    @Test
    func temperatureDescriptorIgnoresNonTemperatureNumericValues() {
        let device = TestSupport.makeDevice(
            uniqueId: "thermo-3",
            name: "Secondary Sensor",
            usage: "sensorThermo",
            data: [
                "reading": .number(21)
            ]
        )

        #expect(device.temperatureDescriptor() == nil)
    }

    @Test
    func temperatureDescriptorIsNilForNonThermoDevices() {
        let device = TestSupport.makeDevice(
            uniqueId: "light-9",
            name: "Garage",
            usage: "light",
            data: ["temperature": .number(19)]
        )

        #expect(device.temperatureDescriptor() == nil)
    }

    @Test
    func thermostatDescriptorBuildsFromBoilerData() {
        let device = TestSupport.makeDevice(
            uniqueId: "boiler-1",
            name: "Living Thermostat",
            usage: "boiler",
            data: [
                "temperature": .number(21.4),
                "hygroIn": .number(48),
                "setpoint": .number(22.5)
            ],
            metadata: [
                "temperature": .object(["unit": .string("degC")]),
                "setpoint": .object([
                    "min": .number(10),
                    "max": .number(30),
                    "step": .number(0.5),
                    "unit": .string("degC")
                ])
            ]
        )

        let descriptor = device.thermostatDescriptor()

        #expect(descriptor?.temperature?.value == 21.4)
        #expect(descriptor?.humidity?.value == 48)
        #expect(descriptor?.setpointKey == "setpoint")
        #expect(descriptor?.setpoint == 22.5)
        #expect(descriptor?.setpointRange == 10...30)
        #expect(descriptor?.setpointStep == 0.5)
        #expect(descriptor?.unitSymbol == "°C")
    }

    @Test
    func thermostatDescriptorSupportsRe2020ControlBoilerPayload() {
        let device = TestSupport.makeDevice(
            uniqueId: "thermic-1",
            name: "Thermostat",
            usage: "re2020ControlBoiler",
            data: [
                "ambientTemperature": .number(24.1),
                "hygroIn": .number(52),
                "setpoint": .number(25.0),
                "__linkedAreaId": .number(1739197415)
            ],
            metadata: [
                "setpoint": .object(["min": .number(10), "max": .number(30), "step": .number(0.5)])
            ]
        )

        let descriptor = device.thermostatDescriptor()

        #expect(device.group == .boiler)
        #expect(descriptor?.temperature?.key == "ambientTemperature")
        #expect(descriptor?.humidity?.key == "hygroIn")
        #expect(descriptor?.setpoint == 25.0)
        #expect(descriptor?.canAdjustSetpoint == true)
    }

    @Test
    func observationEquivalenceIgnoresUpdatedAtAndUnrelatedMetadata() {
        let baseline = TestSupport.makeDevice(
            uniqueId: "light-7",
            name: "Patio",
            usage: "light",
            data: ["on": .bool(true), "level": .number(70)],
            metadata: [
                "level": .object(["min": .number(0), "max": .number(100)]),
                "heartbeat": .number(1)
            ]
        )

        var changed = baseline
        changed.updatedAt = baseline.updatedAt.addingTimeInterval(5)
        changed.metadata = [
            "level": .object(["min": .number(0), "max": .number(100)]),
            "heartbeat": .number(2)
        ]

        #expect(baseline.isEquivalentForObservation(to: changed))
    }

    @Test
    func observationEquivalenceDetectsMeaningfulControlChange() {
        let baseline = TestSupport.makeDevice(
            uniqueId: "light-8",
            name: "Garage",
            usage: "light",
            data: ["on": .bool(false), "level": .number(20)],
            metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
        )

        var changed = baseline
        changed.data["level"] = .number(65)

        #expect(!baseline.isEquivalentForObservation(to: changed))
    }

    @Test
    func favoritesEquivalenceIgnoresUpdatedAtButTracksVisibleStatus() {
        let baseline = TestSupport.makeDevice(
            uniqueId: "window-1",
            name: "Kitchen Window",
            usage: "window",
            isFavorite: true,
            dashboardOrder: 0,
            data: ["open": .bool(false)]
        )

        var timeOnlyChange = baseline
        timeOnlyChange.updatedAt = baseline.updatedAt.addingTimeInterval(20)
        #expect(baseline.isEquivalentForFavorites(to: timeOnlyChange))

        var statusChange = baseline
        statusChange.data["open"] = .bool(true)
        #expect(!baseline.isEquivalentForFavorites(to: statusChange))
    }
}
