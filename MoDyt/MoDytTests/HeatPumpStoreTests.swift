import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct HeatPumpStoreTests {
    @Test
    func initUsesInitialThermostatDescriptor() {
        let store = HeatPumpStore(
            uniqueId: "heatpump-1",
            initialDevice: makeHeatPumpDevice(uniqueId: "heatpump-1", setpoint: 21.5),
            dependencies: .init(
                observeHeatPump: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        #expect(store.descriptor?.setpoint == 21.5)
        #expect(store.descriptor?.setpointKey == "setpoint")
        #expect(store.descriptor?.canAdjustSetpoint == true)
    }

    @Test
    func setSetpointDispatchesOptimisticUpdateThenCommand() async {
        let recorder = TestRecorder<String>()
        let store = HeatPumpStore(
            uniqueId: "heatpump-2",
            initialDevice: makeHeatPumpDevice(uniqueId: "heatpump-2", setpoint: 21.0),
            dependencies: .init(
                observeHeatPump: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticChanges: { uniqueId, changes in
                    let value = changes["setpoint"]?.stringValue ?? "nil"
                    await recorder.record("optimistic:\(uniqueId):\(value)")
                },
                sendCommand: { uniqueId, key, value in
                    await recorder.record("command:\(uniqueId):\(key):\(value.stringValue ?? "nil")")
                }
            )
        )

        store.setSetpoint(22.5)
        let didDispatch = await waitUntil {
            let entries = await recorder.values
            return store.descriptor?.setpoint == 22.5
                && entries.contains("optimistic:heatpump-2:22.5")
                && entries.contains("command:heatpump-2:setpoint:22.5")
        }

        #expect(didDispatch)
        #expect(store.descriptor?.setpoint == 22.5)
        let entries = await recorder.values
        #expect(entries.contains("optimistic:heatpump-2:22.5"))
        #expect(entries.contains("command:heatpump-2:setpoint:22.5"))
    }

    @Test
    func incrementAndDecrementUseConfiguredStepAndClampRange() async {
        let recorder = LockedCounter()
        let store = HeatPumpStore(
            uniqueId: "heatpump-3",
            initialDevice: makeHeatPumpDevice(
                uniqueId: "heatpump-3",
                setpoint: 30.0,
                minSetpoint: 10.0,
                maxSetpoint: 30.0,
                step: 0.5
            ),
            dependencies: .init(
                observeHeatPump: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticChanges: { _, _ in
                    recorder.increment()
                },
                sendCommand: { _, _, _ in
                    recorder.increment()
                }
            )
        )

        store.incrementSetpoint()
        let didClampAtMax = await waitUntil {
            store.descriptor?.setpoint == 30.0
        }
        #expect(didClampAtMax)
        #expect(store.descriptor?.setpoint == 30.0)

        store.decrementSetpoint()
        let didDecrement = await waitUntil {
            store.descriptor?.setpoint == 29.5 && recorder.value == 2
        }
        #expect(didDecrement)
        #expect(store.descriptor?.setpoint == 29.5)
        #expect(recorder.value == 2)
    }

    @Test
    func observationUpdatesDescriptorFromIncomingDevice() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = HeatPumpStore(
            uniqueId: "heatpump-4",
            initialDevice: makeHeatPumpDevice(uniqueId: "heatpump-4", setpoint: 20.0),
            dependencies: .init(
                observeHeatPump: { _ in streamBox.stream },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        streamBox.yield(makeHeatPumpDevice(uniqueId: "heatpump-4", setpoint: 23.0))
        let didObserve = await waitUntil {
            store.descriptor?.setpoint == 23.0
        }

        #expect(didObserve)
        #expect(store.descriptor?.setpoint == 23.0)
    }

    @Test
    func pendingSetpointSuppressesStaleEchoBeforeTimeout() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let now = Date(timeIntervalSince1970: 8_000)
        let store = HeatPumpStore(
            uniqueId: "heatpump-5",
            initialDevice: makeHeatPumpDevice(uniqueId: "heatpump-5", setpoint: 20.0),
            dependencies: .init(
                observeHeatPump: { _ in streamBox.stream },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in },
                now: { now }
            )
        )

        store.setSetpoint(22.0)
        let didApplyOptimistic = await waitUntil {
            store.descriptor?.setpoint == 22.0
        }
        #expect(didApplyOptimistic)

        streamBox.yield(makeHeatPumpDevice(uniqueId: "heatpump-5", setpoint: 20.0))
        let remainedSuppressed = await waitUntil {
            store.descriptor?.setpoint == 22.0
        }

        #expect(remainedSuppressed)
        #expect(store.descriptor?.setpoint == 22.0)
    }

    private func makeHeatPumpDevice(
        uniqueId: String,
        setpoint: Double,
        minSetpoint: Double = 10.0,
        maxSetpoint: Double = 30.0,
        step: Double = 0.5
    ) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Heat Pump",
            usage: "boiler",
            data: [
                "temperature": .number(20.2),
                "hygroIn": .number(42),
                "setpoint": .number(setpoint)
            ],
            metadata: [
                "temperature": .object(["unit": .string("degC")]),
                "setpoint": .object([
                    "min": .number(minSetpoint),
                    "max": .number(maxSetpoint),
                    "step": .number(step),
                    "unit": .string("degC")
                ])
            ]
        )
    }
}
