import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct DevicesStoreTests {
    @Test
    func groupsDevicesFromStream() async {
        let streamBox = BufferedStreamBox<[DeviceRecord]>()
        let store = DevicesStore(
            dependencies: .init(
                observeDevices: { streamBox.stream },
                toggleFavorite: { _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        streamBox.yield(
            [
                TestSupport.makeDevice(uniqueId: "light-z", name: "Zulu Light", usage: "light", data: ["on": .bool(false)]),
                TestSupport.makeDevice(uniqueId: "light-a", name: "Alpha Light", usage: "light", data: ["on": .bool(false)]),
                TestSupport.makeDevice(uniqueId: "shutter-1", name: "Main Shutter", usage: "shutter", data: ["level": .number(0)])
            ]
        )
        await settleAsyncState()

        #expect(store.state.groupedDevices.count == 2)
        #expect(store.state.groupedDevices.map(\.group) == [.shutter, .light])
        #expect(store.state.groupedDevices[1].devices.map(\.name) == ["Alpha Light", "Zulu Light"])
    }

    @Test
    func toggleAndRefreshDispatchEffects() async {
        let recorder = TestRecorder<String>()
        let store = DevicesStore(
            dependencies: .init(
                observeDevices: {
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                toggleFavorite: { uniqueId in
                    await recorder.record("toggle:\(uniqueId)")
                },
                refreshAll: {
                    await recorder.record("refresh")
                }
            )
        )

        store.send(.toggleFavorite("device-1"))
        store.send(.refreshRequested)
        await settleAsyncState()

        let entries = await recorder.values
        #expect(entries.contains("toggle:device-1"))
        #expect(entries.contains("refresh"))
    }

    @Test
    func onAppearStartsObservationOnlyOnce() async {
        let streamBox = BufferedStreamBox<[DeviceRecord]>()
        let observeCounter = Counter()

        let store = DevicesStore(
            dependencies: .init(
                observeDevices: {
                    await observeCounter.increment()
                    return streamBox.stream
                },
                toggleFavorite: { _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        store.send(.onAppear)
        await settleAsyncState()

        #expect(await observeCounter.value == 1)
    }
}
