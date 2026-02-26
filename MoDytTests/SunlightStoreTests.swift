import Foundation
import Testing
@testable import MoDyt

@MainActor
struct SunlightDescriptorTests {
    @Test
    func sunlightDescriptorUsesPreferredKeyWithDefaultRange() async {
        let streamBox = BufferedStreamBox<Device?>()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeSunlightRepositoryDevice(
                id: "sun-1",
                name: "Ensoleillement",
                usage: "unknownSunSensor",
                data: [
                    "lightPower": .number(860),
                    "battery": .number(95)
                ]
            )
        )

        let didObserve = await waitUntil {
            store.descriptor?.key == "lightPower"
        }

        #expect(didObserve)
        #expect(store.descriptor?.key == "lightPower")
        #expect(store.descriptor?.value == 860)
        #expect(store.descriptor?.range == 0...1400)
        #expect(store.descriptor?.unitSymbol == "W/m2")
        #expect(store.descriptor?.batteryStatus?.batteryLevelKey == "battery")
        #expect(store.descriptor?.batteryStatus?.batteryLevel == 95)
    }

    @Test
    func sunlightDescriptorConvertsKilowattUnitToWattsPerSquareMeter() async {
        let streamBox = BufferedStreamBox<Device?>()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeSunlightRepositoryDevice(
                id: "sun-2",
                name: "Roof Sensor",
                usage: "weather",
                data: [
                    "solarRadiation": .number(1.1)
                ],
                metadata: [
                    "solarRadiation": .object([
                        "unit": .string("kW/m2"),
                        "min": .number(0),
                        "max": .number(1.4)
                    ])
                ]
            )
        )

        let didObserve = await waitUntil {
            store.descriptor?.key == "solarRadiation"
        }

        #expect(didObserve)
        #expect(store.descriptor?.value == 1100)
        #expect(store.descriptor?.range == 0...1400)
        #expect(store.descriptor?.unitSymbol == "W/m2")
    }

    private func makeStore(streamBox: BufferedStreamBox<Device?>) -> SunlightStore {
        SunlightStore(
            dependencies: .init(
                observeSunlight: { streamBox.stream }
            )
        )
    }

    private func makeSunlightRepositoryDevice(
        id: String,
        name: String,
        usage: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]? = nil
    ) -> Device {
        Device(
            id: id,
            endpointId: 1,
            name: name,
            usage: usage,
            kind: "sensor",
            data: data,
            metadata: metadata,
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }
}

@MainActor
struct SunlightStoreTests {
    @Test
    func initUsesInitialDescriptor() {
        let store = SunlightStore(
            initialDescriptor: makeSunlightDescriptor(value: 320, batteryDefect: false),
            dependencies: .init(
                observeSunlight: {
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                }
            )
        )

        #expect(store.descriptor?.value == 320)
        #expect(store.descriptor?.unitSymbol == "W/m2")
        #expect(store.descriptor?.batteryStatus?.batteryDefect == false)
    }

    @Test
    func observationUpdatesDescriptorFromIncomingDescriptor() async {
        let streamBox = BufferedStreamBox<Device?>()
        let store = SunlightStore(
            initialDescriptor: makeSunlightDescriptor(value: 250),
            dependencies: .init(
                observeSunlight: { streamBox.stream }
            )
        )

        streamBox.yield(
            makeSunlightRepositoryDevice(
                id: "sun-11",
                name: "Sunlight",
                usage: "weather",
                data: ["lightPower": .number(740)]
            )
        )
        let didObserve = await waitUntil {
            store.descriptor?.value == 740
        }

        #expect(didObserve)
        #expect(store.descriptor?.value == 740)
    }

    @Test
    func observationClearsDescriptorWhenDeviceDisappears() async {
        let streamBox = BufferedStreamBox<Device?>()
        let store = SunlightStore(
            initialDescriptor: makeSunlightDescriptor(value: 180),
            dependencies: .init(
                observeSunlight: { streamBox.stream }
            )
        )

        streamBox.yield(nil)
        let didClear = await waitUntil {
            store.descriptor == nil
        }

        #expect(didClear)
        #expect(store.descriptor == nil)
    }

    private func makeSunlightRepositoryDevice(
        id: String,
        name: String,
        usage: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]? = nil
    ) -> Device {
        Device(
            id: id,
            endpointId: 1,
            name: name,
            usage: usage,
            kind: "sensor",
            data: data,
            metadata: metadata,
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }

    private func makeSunlightDescriptor(
        value: Double,
        batteryDefect: Bool? = nil,
        batteryLevel: Double? = nil
    ) -> SunlightStore.Descriptor {
        SunlightStore.Descriptor(
            key: "lightPower",
            value: value,
            range: 0...1400,
            unitSymbol: "W/m2",
            batteryStatus: SunlightStore.Descriptor.BatteryStatus(
                batteryDefectKey: batteryDefect == nil ? nil : "battDefect",
                batteryDefect: batteryDefect,
                batteryLevelKey: batteryLevel == nil ? nil : "battery",
                batteryLevel: batteryLevel
            )
        )
    }
}
