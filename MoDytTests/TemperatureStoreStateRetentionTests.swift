import Foundation
import Testing
@testable import MoDyt

@MainActor
struct TemperatureStoreStateRetentionTests {
    @Test
    func transientNilDescriptorKeepsLastValidValue() async {
        let streamBox = DeviceStreamBox()
        let store = TemperatureStore(
            dependencies: .init(
                observeTemperature: { _ in streamBox.stream }
            ),
            identifier: .init(deviceId: 42, endpointId: 1)
        )
        store.start()

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: ["temperature": .number(20.0)]
            )
        )

        let didReceiveValidValue = await waitUntil {
            store.descriptor?.value == 20.0
        }
        #expect(didReceiveValidValue)

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: [
                    "temperature": .null,
                    "authorization": .string("HEATING")
                ]
            )
        )

        await Task.yield()
        #expect(store.descriptor?.value == 20.0)
    }

    @Test
    func deviceRemovalClearsDescriptor() async {
        let streamBox = DeviceStreamBox()
        let store = TemperatureStore(
            dependencies: .init(
                observeTemperature: { _ in streamBox.stream }
            ),
            identifier: .init(deviceId: 42, endpointId: 1)
        )
        store.start()

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: ["temperature": .number(20.0)]
            )
        )

        let didReceiveValidValue = await waitUntil {
            store.descriptor?.value == 20.0
        }
        #expect(didReceiveValidValue)

        streamBox.yield(nil)

        let didClear = await waitUntil {
            store.descriptor == nil
        }

        #expect(didClear)
        #expect(store.descriptor == nil)
    }

    private func makeDevice(
        usage: String,
        data: [String: JSONValue]
    ) -> Device {
        Device(
            id: .init(deviceId: 42, endpointId: 1),
            deviceId: 42,
            endpointId: 1,
            name: "Temperature",
            usage: usage,
            kind: "kind",
            data: data,
            metadata: nil,
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
