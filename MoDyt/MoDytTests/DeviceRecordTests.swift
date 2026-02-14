import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct DeviceRecordTests {
    @Test(arguments: DrivingLightDescriptorCase.allCases)
    func drivingLightControlDescriptorMapsExpectedValues(_ testCase: DrivingLightDescriptorCase) throws {
        let device = TestSupport.makeDevice(
            uniqueId: testCase.uniqueId,
            name: testCase.name,
            usage: "light",
            data: testCase.data,
            metadata: testCase.metadata
        )

        let descriptor = try #require(device.drivingLightControlDescriptor())

        #expect(descriptor.powerKey == testCase.expectedPowerKey)
        #expect(descriptor.levelKey == testCase.expectedLevelKey)
        #expect(descriptor.isOn == testCase.expectedIsOn)
        #expect(descriptor.level == testCase.expectedLevel)
        #expect(descriptor.percentage == testCase.expectedPercentage)
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
    func temperatureDescriptorUsesPreferredKeyAndNormalizesUnit() throws {
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

        let descriptor = try #require(device.temperatureDescriptor())
        let batteryStatus = try #require(descriptor.batteryStatus)

        #expect(descriptor.key == "temperature")
        #expect(descriptor.value == 18.4)
        #expect(descriptor.unitSymbol == "°C")
        #expect(batteryStatus.batteryLevelKey == "battery")
        #expect(batteryStatus.batteryLevel == 92)
    }

    @Test
    func temperatureDescriptorPrefersOutTemperatureOverConfigValue() throws {
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

        let descriptor = try #require(device.temperatureDescriptor())

        #expect(descriptor.key == "outTemperature")
        #expect(descriptor.value == 11.0)
        #expect(descriptor.unitSymbol == "°C")
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
    func thermostatDescriptorBuildsFromBoilerData() throws {
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

        let descriptor = try #require(device.thermostatDescriptor())
        let temperature = try #require(descriptor.temperature)
        let humidity = try #require(descriptor.humidity)

        #expect(temperature.value == 21.4)
        #expect(humidity.value == 48)
        #expect(descriptor.setpointKey == "setpoint")
        #expect(descriptor.setpoint == 22.5)
        #expect(descriptor.setpointRange == 10...30)
        #expect(descriptor.setpointStep == 0.5)
        #expect(descriptor.unitSymbol == "°C")
    }

    @Test
    func thermostatDescriptorSupportsRe2020ControlBoilerPayload() throws {
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

        let descriptor = try #require(device.thermostatDescriptor())
        let temperature = try #require(descriptor.temperature)
        let humidity = try #require(descriptor.humidity)

        #expect(device.group == .boiler)
        #expect(temperature.key == "ambientTemperature")
        #expect(humidity.key == "hygroIn")
        #expect(descriptor.setpoint == 25.0)
        #expect(descriptor.canAdjustSetpoint == true)
    }

    @Test
    func energyConsumptionDescriptorUsesEnergyIndexAndDefaultRange() throws {
        let device = TestSupport.makeDevice(
            uniqueId: "energy-1",
            name: "Consumption",
            usage: "conso",
            data: [
                "energyIndex_ELEC": .number(186.5)
            ]
        )

        let descriptor = try #require(device.energyConsumptionDescriptor())

        #expect(descriptor.key == "energyIndex_ELEC")
        #expect(descriptor.value == 186.5)
        #expect(descriptor.range == 0...864)
        #expect(descriptor.unitSymbol == "kWh")
    }

    @Test
    func energyConsumptionDescriptorConvertsWhToKWh() throws {
        let device = TestSupport.makeDevice(
            uniqueId: "energy-2",
            name: "Consumption",
            usage: "conso",
            data: [
                "energyIndex_ELEC": .number(1200)
            ],
            metadata: [
                "energyIndex_ELEC": .object([
                    "unit": .string("Wh")
                ])
            ]
        )

        let descriptor = try #require(device.energyConsumptionDescriptor())

        #expect(descriptor.value == 1.2)
        #expect(descriptor.unitSymbol == "kWh")
    }

    @Test
    func sunlightDescriptorExtractsBatteryStatus() throws {
        let device = TestSupport.makeDevice(
            uniqueId: "sun-1",
            name: "Garden Sun",
            usage: "sensorSun",
            data: [
                "lightPower": .number(620),
                "battDefect": .bool(false),
                "battery": .number(87)
            ]
        )

        let descriptor = try #require(device.sunlightDescriptor())
        let batteryStatus = try #require(descriptor.batteryStatus)

        #expect(descriptor.key == "lightPower")
        #expect(batteryStatus.batteryDefectKey == "battDefect")
        #expect(batteryStatus.batteryDefect == false)
        #expect(batteryStatus.batteryLevelKey == "battery")
        #expect(batteryStatus.batteryLevel == 87)
    }

    @Test
    func smokeDetectorDescriptorExtractsSmokeAndBatteryDefect() throws {
        let device = TestSupport.makeDevice(
            uniqueId: "smoke-1",
            name: "Hallway Smoke",
            usage: "sensorDFR",
            data: [
                "techSmokeDefect": .bool(false),
                "battDefect": .bool(true)
            ]
        )

        let descriptor = try #require(device.smokeDetectorDescriptor())

        #expect(device.group == .smoke)
        #expect(descriptor.smokeKey == "techSmokeDefect")
        #expect(descriptor.smokeDetected == false)
        #expect(descriptor.batteryDefectKey == "battDefect")
        #expect(descriptor.batteryDefect == true)
        #expect(descriptor.health == .notOk)
    }

    @Test
    func smokeDetectorDescriptorExtractsBatteryLevel() throws {
        let device = TestSupport.makeDevice(
            uniqueId: "smoke-2",
            name: "Kitchen Smoke",
            usage: "sensorDFR",
            data: [
                "techSmokeDefect": .bool(false),
                "battLevel": .number(84)
            ]
        )

        let descriptor = try #require(device.smokeDetectorDescriptor())

        #expect(descriptor.batteryLevelKey == "battLevel")
        #expect(descriptor.batteryLevel == 84)
        #expect(descriptor.health == .ok)
    }

    @Test
    func smokeDetectorDescriptorIsNilWithoutSmokeSignal() {
        let device = TestSupport.makeDevice(
            uniqueId: "smoke-3",
            name: "Attic Smoke",
            usage: "sensorDFR",
            data: [
                "battDefect": .bool(false)
            ]
        )

        #expect(device.smokeDetectorDescriptor() == nil)
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

private struct DrivingLightDescriptorCase: Sendable {
    let uniqueId: String
    let name: String
    let data: [String: JSONValue]
    let metadata: [String: JSONValue]?
    let expectedPowerKey: String?
    let expectedLevelKey: String?
    let expectedIsOn: Bool
    let expectedLevel: Double
    let expectedPercentage: Int

    static let allCases: [DrivingLightDescriptorCase] = [
        .init(
            uniqueId: "light-1",
            name: "Driveway",
            data: ["on": .bool(true), "level": .number(50)],
            metadata: ["level": .object(["min": .number(0), "max": .number(200)])],
            expectedPowerKey: "on",
            expectedLevelKey: "level",
            expectedIsOn: true,
            expectedLevel: 50,
            expectedPercentage: 25
        ),
        .init(
            uniqueId: "light-2",
            name: "Garage",
            data: ["state": .bool(false)],
            metadata: nil,
            expectedPowerKey: "state",
            expectedLevelKey: nil,
            expectedIsOn: false,
            expectedLevel: 0,
            expectedPercentage: 0
        ),
        .init(
            uniqueId: "light-3",
            name: "Porch",
            data: ["level": .number(35)],
            metadata: ["level": .object(["min": .number(0), "max": .number(70)])],
            expectedPowerKey: nil,
            expectedLevelKey: "level",
            expectedIsOn: true,
            expectedLevel: 35,
            expectedPercentage: 50
        )
    ]
}
