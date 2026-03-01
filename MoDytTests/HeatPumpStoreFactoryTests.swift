import Foundation
import Testing
@testable import MoDyt

struct HeatPumpStoreFactoryTests {
    @Test
    func mergesSiblingEndpointSignalsWhenPrimaryMissesSetpoint() {
        let primaryIdentifier = DeviceIdentifier(deviceId: 42, endpointId: 1)
        let siblingIdentifier = DeviceIdentifier(deviceId: 42, endpointId: 2)

        let primary = makeDevice(
            identifier: primaryIdentifier,
            data: [
                "temperature": .number(20.9)
            ]
        )
        let sibling = makeDevice(
            identifier: siblingIdentifier,
            data: [
                "setpoint": .number(21.0)
            ]
        )
        let unrelated = makeDevice(
            identifier: .init(deviceId: 99, endpointId: 1),
            data: [
                "temperature": .number(18.0),
                "setpoint": .number(18.5)
            ]
        )

        let resolved = HeatPumpStoreFactory.resolveObservedDevice(
            for: primaryIdentifier,
            in: [unrelated, sibling, primary]
        )

        #expect(resolved?.id == primaryIdentifier)
        #expect(resolved?.heatPumpGatewayValues()?.temperature == 20.9)
        #expect(resolved?.heatPumpGatewayValues()?.setPoint == 21.0)
        #expect(resolved?.heatPumpSetpointKey() == "setpoint")
    }

    @Test
    func primaryEndpointValuesWinWhenSignalKeysOverlap() {
        let primaryIdentifier = DeviceIdentifier(deviceId: 42, endpointId: 1)

        let primary = makeDevice(
            identifier: primaryIdentifier,
            data: [
                "temperature": .number(20.9),
                "setpoint": .number(19.5)
            ]
        )
        let sibling = makeDevice(
            identifier: .init(deviceId: 42, endpointId: 2),
            data: [
                "setpoint": .number(22.0)
            ]
        )

        let resolved = HeatPumpStoreFactory.resolveObservedDevice(
            for: primaryIdentifier,
            in: [sibling, primary]
        )

        #expect(resolved?.heatPumpGatewayValues()?.setPoint == 19.5)
    }

    @Test
    func returnsNilWhenNoEndpointSharesRequestedDeviceID() {
        let resolved = HeatPumpStoreFactory.resolveObservedDevice(
            for: .init(deviceId: 42, endpointId: 1),
            in: [
                makeDevice(
                    identifier: .init(deviceId: 99, endpointId: 1),
                    data: [
                        "temperature": .number(18.0),
                        "setpoint": .number(18.5)
                    ]
                )
            ]
        )

        #expect(resolved == nil)
    }

    private func makeDevice(
        identifier: DeviceIdentifier,
        data: [String: JSONValue]
    ) -> Device {
        Device(
            id: identifier,
            deviceId: identifier.deviceId,
            endpointId: identifier.endpointId,
            name: "Heat Pump",
            usage: "sh_hvac",
            kind: "heatpump",
            data: data,
            metadata: nil,
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }
}
