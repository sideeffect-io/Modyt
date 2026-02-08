import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct DashboardDeviceCardStoreTests {
    @Test
    func observesDeviceByUniqueId() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let store = DashboardDeviceCardStore(
            uniqueId: "light-1",
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                applyOptimisticUpdate: { _, _, _ in },
                sendDeviceCommand: { _, _, _ in }
            )
        )

        store.send(.onAppear)
        streamBox.yield(
            TestSupport.makeDevice(
                uniqueId: "light-1",
                name: "Desk",
                usage: "light",
                data: ["on": .bool(false)]
            )
        )
        await settleAsyncState()

        #expect(store.state.device?.uniqueId == "light-1")
    }

    @Test
    func nonShutterControlDispatchesOptimisticAndCommand() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let recorder = TestRecorder<String>()

        let store = DashboardDeviceCardStore(
            uniqueId: "light-1",
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                applyOptimisticUpdate: { uniqueId, key, value in
                    await recorder.record("optimistic:\(uniqueId):\(key):\(value.boolValue == true)")
                },
                sendDeviceCommand: { uniqueId, key, value in
                    await recorder.record("command:\(uniqueId):\(key):\(value.boolValue == true)")
                }
            )
        )

        store.send(.onAppear)
        streamBox.yield(
            TestSupport.makeDevice(
                uniqueId: "light-1",
                name: "Desk",
                usage: "light",
                data: ["on": .bool(false)]
            )
        )
        await settleAsyncState()

        store.send(.controlChanged(key: "on", value: .bool(true)))
        await settleAsyncState()

        let entries = await recorder.values
        #expect(entries.contains("optimistic:light-1:on:true"))
        #expect(entries.contains("command:light-1:on:true"))
    }

    @Test
    func shutterSliderControlOnlyDispatchesCommand() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let recorder = TestRecorder<String>()

        let store = DashboardDeviceCardStore(
            uniqueId: "shutter-1",
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                applyOptimisticUpdate: { _, _, _ in
                    await recorder.record("optimistic")
                },
                sendDeviceCommand: { uniqueId, key, _ in
                    await recorder.record("command:\(uniqueId):\(key)")
                }
            )
        )

        store.send(.onAppear)
        streamBox.yield(
            TestSupport.makeDevice(
                uniqueId: "shutter-1",
                name: "Main",
                usage: "shutter",
                data: ["level": .number(0)],
                metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
            )
        )
        await settleAsyncState()

        store.send(.controlChanged(key: "level", value: .number(75)))
        await settleAsyncState()

        let entries = await recorder.values
        #expect(entries == ["command:shutter-1:level"])
    }

    @Test
    func missingDeviceDoesNotDispatchControlSideEffects() async {
        let recorder = TestRecorder<String>()
        let store = DashboardDeviceCardStore(
            uniqueId: "missing",
            dependencies: .init(
                observeDevice: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                applyOptimisticUpdate: { _, _, _ in
                    await recorder.record("optimistic")
                },
                sendDeviceCommand: { _, _, _ in
                    await recorder.record("command")
                }
            )
        )

        store.send(.controlChanged(key: "on", value: .bool(true)))
        await settleAsyncState()

        let entries = await recorder.values
        #expect(entries.isEmpty)
    }

    @Test
    func onAppearStartsObservationOnlyOnce() async {
        let streamBox = BufferedStreamBox<DeviceRecord?>()
        let observeCounter = Counter()

        let store = DashboardDeviceCardStore(
            uniqueId: "device-1",
            dependencies: .init(
                observeDevice: { _ in
                    await observeCounter.increment()
                    return streamBox.stream
                },
                applyOptimisticUpdate: { _, _, _ in },
                sendDeviceCommand: { _, _, _ in }
            )
        )

        store.send(.onAppear)
        store.send(.onAppear)
        await settleAsyncState()

        #expect(await observeCounter.value == 1)
    }
}
