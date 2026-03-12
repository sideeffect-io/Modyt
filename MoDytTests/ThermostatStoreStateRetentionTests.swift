import Foundation
import Testing
@testable import MoDyt

@MainActor
struct ThermostatStoreStateRetentionTests {
    @Test
    func transientNilDescriptorKeepsLastValidState() async {
        let streamBox = DeviceStreamBox()
        let store = ThermostatStore(
            observeThermostat: .init(
                observeThermostat: { streamBox.stream }
            )
        )
        store.start()

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: [
                    "temperature": .number(19.8),
                    "setpoint": .number(20.0)
                ]
            )
        )

        let didReceiveValidState = await waitUntil {
            store.state?.temperature?.value == 19.8
        }
        #expect(didReceiveValidState)

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: [
                    "temperature": .null,
                    "setpoint": .null,
                    "authorization": .string("HEATING")
                ]
            )
        )

        await Task.yield()
        #expect(store.state?.temperature?.value == 19.8)
    }

    @Test
    func deviceRemovalClearsState() async {
        let streamBox = DeviceStreamBox()
        let store = ThermostatStore(
            observeThermostat: .init(
                observeThermostat: { streamBox.stream }
            )
        )
        store.start()

        streamBox.yield(
            makeDevice(
                usage: "boiler",
                data: [
                    "temperature": .number(19.8),
                    "setpoint": .number(20.0)
                ]
            )
        )

        let didReceiveValidState = await waitUntil {
            store.state != nil
        }
        #expect(didReceiveValidState)

        streamBox.yield(nil)

        let didClear = await waitUntil {
            store.state == nil
        }
        #expect(didClear)
        #expect(store.state == nil)
    }

    private func makeDevice(
        usage: String,
        data: [String: JSONValue]
    ) -> Device {
        Device(
            id: .init(deviceId: 42, endpointId: 1),
            deviceId: 42,
            endpointId: 1,
            name: "Thermostat",
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
