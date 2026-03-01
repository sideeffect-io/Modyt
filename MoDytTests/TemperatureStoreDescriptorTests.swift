import Foundation
import Testing
@testable import MoDyt

@MainActor
struct TemperatureStoreDescriptorTests {
    @Test
    func acceptsRegTemperatureAsCurrentTemperature() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeDevice(
                usage: "sh_hvac",
                data: [
                    "regTemperature": .number(21.4),
                    "currentSetpoint": .number(22.0)
                ]
            )
        )

        let didReceive = await waitUntil {
            store.descriptor?.value == 21.4
        }

        #expect(didReceive)
        #expect(store.descriptor?.value == 21.4)
    }

    @Test
    func acceptsAmbientTemperatureFallback() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: [
                    "ambientTemperature": .number(19.2)
                ]
            )
        )

        let didReceive = await waitUntil {
            store.descriptor?.value == 19.2
        }

        #expect(didReceive)
        #expect(store.descriptor?.value == 19.2)
    }

    @Test
    func normalizesTemperatureUnitFromMetadata() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: [
                    "temperature": .number(20.5)
                ],
                metadata: [
                    "temperature": .object(["unit": .string("degC")])
                ]
            )
        )

        let didReceive = await waitUntil {
            store.descriptor?.unitSymbol == "°C"
        }

        #expect(didReceive)
        #expect(store.descriptor?.unitSymbol == "°C")
    }

    @Test
    func ignoresFalsePositiveTemperatureKeys() async {
        let streamBox = DeviceStreamBox()
        let store = makeStore(streamBox: streamBox)

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: [
                    "configTemp": .number(123),
                    "jobsMP": .number(999)
                ]
            )
        )

        let didSetDescriptor = await waitUntil(cycles: 5) {
            store.descriptor != nil
        }

        #expect(didSetDescriptor == false)
        #expect(store.descriptor == nil)
    }

    private func makeStore(streamBox: DeviceStreamBox) -> TemperatureStore {
        TemperatureStore(
            dependencies: .init(
                observeTemperature: { streamBox.stream }
            )
        )
    }

    private func makeDevice(
        usage: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]? = nil
    ) -> Device {
        Device(
            id: .init(deviceId: 42, endpointId: 1),
            deviceId: 42,
            endpointId: 1,
            name: "Device",
            usage: usage,
            kind: "kind",
            data: data,
            metadata: metadata,
            isFavorite: false,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }

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
