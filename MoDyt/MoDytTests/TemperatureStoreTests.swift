import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct TemperatureStoreTests {
    @Test
    func initUsesInitialThermoDescriptor() {
        let store = TemperatureStore(
            uniqueId: "thermo-1",
            initialDevice: makeThermoDevice(uniqueId: "thermo-1", value: 20.5),
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

    private func makeThermoDevice(uniqueId: String, value: Double) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Outdoor Temperature",
            usage: "sensorThermo",
            data: ["outTemperature": .number(value)],
            metadata: ["outTemperature": .object(["unit": .string("degC")])]
        )
    }
}
