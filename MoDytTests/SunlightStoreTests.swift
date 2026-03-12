import Foundation
import Testing
@testable import MoDyt

@MainActor
struct SunlightDescriptorTests {
    @Test
    func sunlightDescriptorUsesPreferredKeyWithDefaultRange() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeSunlightRepositoryDevice(
                identifier: .init(deviceId: 1, endpointId: 1),
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
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeSunlightRepositoryDevice(
                identifier: .init(deviceId: 2, endpointId: 1),
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

    private func makeStore(streamBox: DeviceStreamBox) -> SunlightStore {
        let store = SunlightStore(
            observeSunlight: .init(
                observeSunlight: { streamBox.stream }
            )
        )
        store.start()
        return store
    }

    private func makeSunlightRepositoryDevice(
        identifier: DeviceIdentifier,
        name: String,
        usage: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]? = nil
    ) -> Device {
        Device(
            id: identifier,
            deviceId: identifier.deviceId,
            endpointId: identifier.endpointId,
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
    func initStartsWithoutDescriptor() {
        let store = SunlightStore(
            observeSunlight: .init(
                observeSunlight: {
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                }
            ),
        )

        #expect(store.descriptor == nil)
    }

    @Test
    func observationUpdatesDescriptorFromIncomingDescriptor() async {
        let streamBox = DeviceStreamBox()
        let store = SunlightStore(
            observeSunlight: .init(
                observeSunlight: { streamBox.stream }
            )
        )
        store.start()

        streamBox.yield(
            makeSunlightRepositoryDevice(
                identifier: .init(deviceId: 11, endpointId: 1),
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
        let streamBox = DeviceStreamBox()
        let store = SunlightStore(
            observeSunlight: .init(
                observeSunlight: { streamBox.stream }
            )
        )
        store.start()

        streamBox.yield(nil)
        let didClear = await waitUntil {
            store.descriptor == nil
        }

        #expect(didClear)
        #expect(store.descriptor == nil)
    }

    private func makeSunlightRepositoryDevice(
        identifier: DeviceIdentifier,
        name: String,
        usage: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]? = nil
    ) -> Device {
        Device(
            id: identifier,
            deviceId: identifier.deviceId,
            endpointId: identifier.endpointId,
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
private func waitUntil(
    cycles: Int = 30,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
}

private final class DeviceStreamBox: @unchecked Sendable {
    let stream: AsyncStream<Device?>

    private let continuation: AsyncStream<Device?>.Continuation

    init() {
        var localContinuation: AsyncStream<Device?>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ value: Device?) {
        continuation.yield(value)
    }
}
