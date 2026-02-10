import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct ShutterStoreTests {
    @Test
    func snapshotUIEquivalenceIgnoresDescriptorValueNoise() {
        let baseline = ShutterSnapshot(
            uniqueId: "shutter-1",
            descriptor: DeviceControlDescriptor(kind: .slider, key: "level", isOn: true, value: 100, range: 0...100),
            actualStep: .open,
            targetStep: nil
        )
        let noisy = ShutterSnapshot(
            uniqueId: "shutter-1",
            descriptor: DeviceControlDescriptor(kind: .slider, key: "level", isOn: true, value: 98, range: 0...100),
            actualStep: .open,
            targetStep: nil
        )

        #expect(ShutterSnapshot.areEquivalentForUI(baseline, noisy))
    }

    @Test
    func snapshotUIEquivalenceDetectsTargetChange() {
        let baseline = ShutterSnapshot(
            uniqueId: "shutter-1",
            descriptor: DeviceControlDescriptor(kind: .slider, key: "level", isOn: true, value: 100, range: 0...100),
            actualStep: .open,
            targetStep: nil
        )
        let withTarget = ShutterSnapshot(
            uniqueId: "shutter-1",
            descriptor: DeviceControlDescriptor(kind: .slider, key: "level", isOn: true, value: 100, range: 0...100),
            actualStep: .open,
            targetStep: .half
        )

        #expect(!ShutterSnapshot.areEquivalentForUI(baseline, withTarget))
    }

    @Test
    func selectEmitsMappedNumericCommandAndSetsTarget() async {
        let setTargetRecorder = TestRecorder<(String, ShutterStep, ShutterStep)>()
        let commandRecorder = TestRecorder<(String, String, JSONValue)>()

        let store = ShutterStore(
            uniqueId: "shutter-1",
            initialDevice: makeShutterDevice(uniqueId: "shutter-1", value: 0),
            dependencies: .init(
                observeShutter: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                setTarget: { uniqueId, targetStep, originStep in
                    await setTargetRecorder.record((uniqueId, targetStep, originStep))
                },
                sendCommand: { uniqueId, key, value in
                    await commandRecorder.record((uniqueId, key, value))
                }
            )
        )

        store.select(.half)
        await settleAsyncState()

        #expect(store.effectiveTargetStep == .half)
        #expect(store.isInFlight)
        let targetUpdates = await setTargetRecorder.values
        #expect(targetUpdates.count == 1)
        #expect(targetUpdates[0].0 == "shutter-1")
        #expect(targetUpdates[0].1 == .half)
        #expect(targetUpdates[0].2 == .closed)

        let commands = await commandRecorder.values
        #expect(commands.count == 1)
        #expect(commands[0].0 == "shutter-1")
        #expect(commands[0].1 == "level")
        #expect(commands[0].2.numberValue == 50)
    }

    @Test
    func selectingCurrentStepDoesNotEmitCommand() async {
        let setTargetRecorder = TestRecorder<(String, ShutterStep, ShutterStep)>()
        let commandRecorder = TestRecorder<(String, String, JSONValue)>()
        let store = ShutterStore(
            uniqueId: "shutter-1",
            initialDevice: makeShutterDevice(uniqueId: "shutter-1", value: 75),
            dependencies: .init(
                observeShutter: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                setTarget: { uniqueId, targetStep, originStep in
                    await setTargetRecorder.record((uniqueId, targetStep, originStep))
                },
                sendCommand: { uniqueId, key, value in
                    await commandRecorder.record((uniqueId, key, value))
                }
            )
        )

        store.select(.threeQuarter)
        await settleAsyncState()

        #expect(store.actualStep == .threeQuarter)
        #expect(!store.isInFlight)
        #expect((await setTargetRecorder.values).isEmpty)
        #expect((await commandRecorder.values).isEmpty)
    }

    @Test
    func observesSnapshotAndUpdatesStateForMatchingUniqueId() async {
        let streamBox = BufferedStreamBox<ShutterSnapshot?>()
        let descriptor = DeviceControlDescriptor(
            kind: .slider,
            key: "level",
            isOn: true,
            value: 25,
            range: 0...100
        )

        let store = ShutterStore(
            uniqueId: "shutter-1",
            initialDevice: makeShutterDevice(uniqueId: "shutter-1", value: 0),
            dependencies: .init(
                observeShutter: { _ in streamBox.stream },
                setTarget: { _, _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        streamBox.yield(
            ShutterSnapshot(
                uniqueId: "shutter-1",
                descriptor: descriptor,
                actualStep: .quarter,
                targetStep: .half
            )
        )
        await settleAsyncState()

        #expect(store.descriptor == descriptor)
        #expect(store.actualStep == .quarter)
        #expect(store.effectiveTargetStep == .half)
        #expect(store.isInFlight)
    }

    @Test
    func ignoresSnapshotsWithDifferentUniqueId() async {
        let streamBox = BufferedStreamBox<ShutterSnapshot?>()
        let baseline = makeShutterDevice(uniqueId: "shutter-1", value: 50)
        let store = ShutterStore(
            uniqueId: "shutter-1",
            initialDevice: baseline,
            dependencies: .init(
                observeShutter: { _ in streamBox.stream },
                setTarget: { _, _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        let initialActual = store.actualStep
        let otherDescriptor = DeviceControlDescriptor(
            kind: .slider,
            key: "level",
            isOn: true,
            value: 100,
            range: 0...100
        )

        streamBox.yield(
            ShutterSnapshot(
                uniqueId: "other",
                descriptor: otherDescriptor,
                actualStep: .open,
                targetStep: .open
            )
        )
        await settleAsyncState()

        #expect(store.actualStep == initialActual)
        #expect(store.descriptor.key == "level")
    }

    @Test
    func syncUpdatesActualBeforeSnapshotButKeepsSnapshotStateAfterward() async {
        let streamBox = BufferedStreamBox<ShutterSnapshot?>()
        let store = ShutterStore(
            uniqueId: "shutter-1",
            initialDevice: makeShutterDevice(uniqueId: "shutter-1", value: 0),
            dependencies: .init(
                observeShutter: { _ in streamBox.stream },
                setTarget: { _, _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        store.sync(device: makeShutterDevice(uniqueId: "shutter-1", value: 75))
        #expect(store.actualStep == .threeQuarter)

        streamBox.yield(
            ShutterSnapshot(
                uniqueId: "shutter-1",
                descriptor: DeviceControlDescriptor(kind: .slider, key: "level", isOn: true, value: 25, range: 0...100),
                actualStep: .quarter,
                targetStep: .half
            )
        )
        await settleAsyncState()

        store.sync(device: makeShutterDevice(uniqueId: "shutter-1", value: 100))
        #expect(store.actualStep == .quarter)
        #expect(store.effectiveTargetStep == .half)
    }

    @Test
    func initWithoutInitialDeviceUsesFallbackDescriptor() {
        let store = ShutterStore(
            uniqueId: "shutter-1",
            initialDevice: nil,
            dependencies: .init(
                observeShutter: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                setTarget: { _, _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        #expect(store.descriptor.kind == .slider)
        #expect(store.descriptor.key == "level")
        #expect(store.descriptor.range == 0...100)
        #expect(store.actualStep == .closed)
        #expect(store.effectiveTargetStep == .closed)
    }

    @Test
    func duplicateSnapshotIsFilteredBeforeReachingStore() async {
        let streamBox = BufferedStreamBox<ShutterSnapshot?>()
        let store = ShutterStore(
            uniqueId: "shutter-1",
            initialDevice: makeShutterDevice(uniqueId: "shutter-1", value: 100),
            dependencies: .init(
                observeShutter: { _ in streamBox.stream.removeDuplicates(by: ShutterSnapshot.areEquivalentForUI) },
                setTarget: { _, _, _ in },
                sendCommand: { _, _, _ in }
            )
        )

        let baseline = ShutterSnapshot(
            uniqueId: "shutter-1",
            descriptor: DeviceControlDescriptor(kind: .slider, key: "level", isOn: true, value: 100, range: 0...100),
            actualStep: .open,
            targetStep: nil
        )

        streamBox.yield(baseline)
        await settleAsyncState()

        store.select(.half)
        #expect(store.effectiveTargetStep == .half)
        #expect(store.isInFlight)

        // Simulates an unrelated repository emission that repeats the same pre-command snapshot.
        streamBox.yield(baseline)
        await settleAsyncState()

        #expect(store.effectiveTargetStep == .half)
        #expect(store.isInFlight)
    }

    private func makeShutterDevice(uniqueId: String, value: Double) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Main Shutter",
            usage: "shutter",
            data: ["level": .number(value)],
            metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
        )
    }
}
