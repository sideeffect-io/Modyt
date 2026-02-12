import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct TemperatureStoreTests {
    @Test
    func initUsesInitialThermoDescriptor() {
        let store = TemperatureStore(
            uniqueId: "thermo-1",
            initialDevice: makeThermoDevice(uniqueId: "thermo-1", value: 20.5, batteryLevel: 78),
            dependencies: .init(
                observeTemperature: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                }
            )
        )

        #expect(store.descriptor?.value == 20.5)
        #expect(store.descriptor?.unitSymbol == "°C")
        #expect(store.descriptor?.batteryStatus?.batteryLevel == 78)
    }

    @Test
    func observationUpdatesDescriptorFromIncomingDevice() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = TemperatureStore(
            uniqueId: "thermo-2",
            initialDevice: makeThermoDevice(uniqueId: "thermo-2", value: 15.2),
            dependencies: .init(
                observeTemperature: { _ in streamBox.stream }
            )
        )

        streamBox.yield(makeThermoDevice(uniqueId: "thermo-2", value: 16.8))
        await settleAsyncState()

        #expect(store.descriptor?.value == 16.8)
    }

    @Test
    func observationClearsDescriptorWhenDeviceDisappears() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = TemperatureStore(
            uniqueId: "thermo-3",
            initialDevice: makeThermoDevice(uniqueId: "thermo-3", value: 12.0),
            dependencies: .init(
                observeTemperature: { _ in streamBox.stream }
            )
        )

        streamBox.yield(nil)
        await settleAsyncState()

        #expect(store.descriptor == nil)
    }

    private func makeThermoDevice(
        uniqueId: String,
        value: Double,
        batteryLevel: Double? = nil,
        batteryDefect: Bool? = nil
    ) -> DeviceRecord {
        var data: [String: JSONValue] = ["outTemperature": .number(value)]
        if let batteryLevel {
            data["battery"] = .number(batteryLevel)
        }
        if let batteryDefect {
            data["battDefect"] = .bool(batteryDefect)
        }

        return TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Outdoor Temperature",
            usage: "sensorThermo",
            data: data,
            metadata: ["outTemperature": .object(["unit": .string("degC")])]
        )
    }
}

@MainActor
struct ThermostatStoreTests {
    @Test
    func initUsesInitialThermostatDescriptor() {
        let store = ThermostatStore(
            uniqueId: "thermostat-1",
            initialDevice: makeThermostatDevice(
                uniqueId: "thermostat-1",
                temperature: 21.2,
                humidity: 47,
                setpoint: 22.0
            ),
            dependencies: .init(
                observeThermostat: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                }
            )
        )

        #expect(store.descriptor?.temperature?.value == 21.2)
        #expect(store.descriptor?.humidity?.value == 47)
    }

    @Test
    func observationUpdatesDescriptorFromIncomingDevice() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = ThermostatStore(
            uniqueId: "thermostat-2",
            initialDevice: makeThermostatDevice(
                uniqueId: "thermostat-2",
                temperature: 20.0,
                humidity: 40,
                setpoint: 21.0
            ),
            dependencies: .init(
                observeThermostat: { _ in streamBox.stream }
            )
        )

        streamBox.yield(
            makeThermostatDevice(
                uniqueId: "thermostat-2",
                temperature: 20.8,
                humidity: 45,
                setpoint: 21.0
            )
        )
        await settleAsyncState()

        #expect(store.descriptor?.temperature?.value == 20.8)
        #expect(store.descriptor?.humidity?.value == 45)
    }

    @Test
    func observationClearsDescriptorWhenDeviceDisappears() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = ThermostatStore(
            uniqueId: "thermostat-3",
            initialDevice: makeThermostatDevice(
                uniqueId: "thermostat-3",
                temperature: 20.0,
                humidity: 40,
                setpoint: 21.0
            ),
            dependencies: .init(
                observeThermostat: { _ in streamBox.stream }
            )
        )

        streamBox.yield(nil)
        await settleAsyncState()

        #expect(store.descriptor == nil)
    }

    private func makeThermostatDevice(
        uniqueId: String,
        temperature: Double,
        humidity: Double,
        setpoint: Double
    ) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Thermostat",
            usage: "boiler",
            data: [
                "temperature": .number(temperature),
                "hygroIn": .number(humidity),
                "setpoint": .number(setpoint)
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
    }
}

@MainActor
struct EnergyConsumptionStoreTests {
    @Test
    func initUsesInitialEnergyConsumptionDescriptor() {
        let store = EnergyConsumptionStore(
            uniqueId: "energy-1",
            initialDevice: makeEnergyDevice(uniqueId: "energy-1", value: 132.2),
            dependencies: .init(
                observeEnergyConsumption: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                }
            )
        )

        #expect(store.descriptor?.value == 132.2)
        #expect(store.descriptor?.unitSymbol == "kWh")
    }

    @Test
    func observationUpdatesDescriptorFromIncomingDevice() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = EnergyConsumptionStore(
            uniqueId: "energy-2",
            initialDevice: makeEnergyDevice(uniqueId: "energy-2", value: 40.0),
            dependencies: .init(
                observeEnergyConsumption: { _ in streamBox.stream }
            )
        )

        streamBox.yield(makeEnergyDevice(uniqueId: "energy-2", value: 88.7))
        await settleAsyncState()

        #expect(store.descriptor?.value == 88.7)
    }

    @Test
    func observationClearsDescriptorWhenDeviceDisappears() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = EnergyConsumptionStore(
            uniqueId: "energy-3",
            initialDevice: makeEnergyDevice(uniqueId: "energy-3", value: 71.0),
            dependencies: .init(
                observeEnergyConsumption: { _ in streamBox.stream }
            )
        )

        streamBox.yield(nil)
        await settleAsyncState()

        #expect(store.descriptor == nil)
    }

    private func makeEnergyDevice(uniqueId: String, value: Double) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Energy",
            usage: "conso",
            data: ["energyIndex_ELEC": .number(value)],
            metadata: ["energyIndex_ELEC": .object(["unit": .string("kWh")])]
        )
    }
}
