import Foundation
import Testing
@testable import MoDyt

struct ThermostatDescriptorTests {
    @Test
    func extractsSetpointWhenTemperatureIsMissing() {
        let device = makeDevice(
            usage: "boiler",
            data: [
                "temperature": .null,
                "setpoint": .number(20.0)
            ]
        )

        let descriptor = device.thermostatDescriptor()

        #expect(descriptor?.temperature == nil)
        #expect(descriptor?.setpoint?.value == 20.0)
    }

    @Test
    func acceptsRegTemperatureAsThermostatTemperature() {
        let device = makeDevice(
            usage: "sh_hvac",
            data: [
                "regTemperature": .number(22.1)
            ],
            metadata: [
                "regTemperature": .object(["unit": .string("celsius")])
            ]
        )

        let descriptor = device.thermostatDescriptor()

        #expect(descriptor?.temperature?.value == 22.1)
        #expect(descriptor?.temperature?.unitSymbol == "°C")
    }

    @Test
    func normalizesHumidityUnit() {
        let device = makeDevice(
            usage: "boiler",
            data: [
                "hygroIn": .number(62)
            ],
            metadata: [
                "hygroIn": .object(["unit": .string("percent")])
            ]
        )

        let descriptor = device.thermostatDescriptor()

        #expect(descriptor?.humidity?.value == 62)
        #expect(descriptor?.humidity?.unitSymbol == "%")
    }

    @Test
    func ignoresFalsePositiveTemperatureKeys() {
        let device = makeDevice(
            usage: "boiler",
            data: [
                "configTemp": .number(200),
                "jobsMP": .number(900)
            ]
        )

        #expect(device.thermostatDescriptor() == nil)
    }

    private func makeDevice(
        usage: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]? = nil
    ) -> Device {
        Device(
            id: "1_42",
            endpointId: 1,
            name: "Thermostat",
            usage: usage,
            kind: "kind",
            data: data,
            metadata: metadata,
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }
}
