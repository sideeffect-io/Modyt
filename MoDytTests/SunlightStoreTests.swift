import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct SunlightDescriptorTests {
    @Test
    func sunlightDescriptorUsesPreferredKeyWithDefaultRange() {
        let device = TestSupport.makeDevice(
            uniqueId: "sun-1",
            name: "Ensoleillement",
            usage: "unknownSunSensor",
            data: [
                "lightPower": .number(860),
                "battery": .number(95)
            ]
        )

        let descriptor = device.sunlightDescriptor()

        #expect(descriptor?.key == "lightPower")
        #expect(descriptor?.value == 860)
        #expect(descriptor?.range == 0...1400)
        #expect(descriptor?.unitSymbol == "W/m2")
        #expect(descriptor?.batteryStatus?.batteryLevelKey == "battery")
        #expect(descriptor?.batteryStatus?.batteryLevel == 95)
    }

    @Test
    func sunlightDescriptorConvertsKilowattUnitToWattsPerSquareMeter() {
        let device = TestSupport.makeDevice(
            uniqueId: "sun-2",
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

        let descriptor = device.sunlightDescriptor()

        #expect(descriptor?.value == 1100)
        #expect(descriptor?.range == 0...1400)
        #expect(descriptor?.unitSymbol == "W/m2")
    }
}

@MainActor
struct SunlightStoreTests {
    @Test
    func initUsesInitialDescriptor() {
        let store = SunlightStore(
            uniqueId: "sun-10",
            initialDevice: makeSunlightDevice(uniqueId: "sun-10", value: 320, batteryDefect: false),
            dependencies: .init(
                observeSunlight: { _ in
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
    func observationUpdatesDescriptorFromIncomingDevice() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = SunlightStore(
            uniqueId: "sun-11",
            initialDevice: makeSunlightDevice(uniqueId: "sun-11", value: 250),
            dependencies: .init(
                observeSunlight: { _ in streamBox.stream }
            )
        )

        streamBox.yield(makeSunlightDevice(uniqueId: "sun-11", value: 740))
        let didObserve = await waitUntil {
            store.descriptor?.value == 740
        }

        #expect(didObserve)
        #expect(store.descriptor?.value == 740)
    }

    @Test
    func observationClearsDescriptorWhenDeviceDisappears() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = SunlightStore(
            uniqueId: "sun-12",
            initialDevice: makeSunlightDevice(uniqueId: "sun-12", value: 180),
            dependencies: .init(
                observeSunlight: { _ in streamBox.stream }
            )
        )

        streamBox.yield(nil)
        let didClear = await waitUntil {
            store.descriptor == nil
        }

        #expect(didClear)
        #expect(store.descriptor == nil)
    }

    private func makeSunlightDevice(
        uniqueId: String,
        value: Double,
        batteryDefect: Bool? = nil,
        batteryLevel: Double? = nil
    ) -> DeviceRecord {
        var data: [String: JSONValue] = ["lightPower": .number(value)]
        if let batteryDefect {
            data["battDefect"] = .bool(batteryDefect)
        }
        if let batteryLevel {
            data["battery"] = .number(batteryLevel)
        }

        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Ensoleillement",
            usage: "unknownSunSensor",
            data: data,
            metadata: ["lightPower": .object(["unit": .string("W/m2")])]
        )
    }
}
