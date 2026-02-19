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
        let didGroup = await waitUntil {
            store.state.groupedDevices.count == 2
                && store.state.groupedDevices.map(\.group) == [.shutter, .light]
                && store.state.groupedDevices[1].devices.map(\.name) == ["Alpha Light", "Zulu Light"]
        }
        streamBox.finish()

        #expect(didGroup)
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
        let didDispatch = await waitUntil {
            let entries = await recorder.values
            return entries.contains("toggle:device-1")
                && entries.contains("refresh")
        }

        #expect(didDispatch)
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
        let observedOnce = await waitUntil {
            await observeCounter.value == 1
        }

        #expect(observedOnce)
        #expect(await observeCounter.value == 1)
    }

    @Test
    func observationRestartsAfterStreamCompletion() async {
        let firstStream = BufferedStreamBox<[DeviceRecord]>()
        let secondStream = BufferedStreamBox<[DeviceRecord]>()
        let observeCounter = Counter()

        let store = DevicesStore(
            dependencies: .init(
                observeDevices: {
                    await observeCounter.increment()
                    let attempt = await observeCounter.value
                    switch attempt {
                    case 1:
                        return firstStream.stream
                    case 2:
                        return secondStream.stream
                    default:
                        return AsyncStream { continuation in
                            continuation.finish()
                        }
                    }
                },
                toggleFavorite: { _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        firstStream.yield([
            TestSupport.makeDevice(uniqueId: "light-1", name: "First", usage: "light", data: ["on": .bool(true)])
        ])
        let didLoadFirst = await waitUntil {
            store.state.groupedDevices.flatMap(\.devices).map(\.name) == ["First"]
        }
        #expect(didLoadFirst)
        #expect(store.state.groupedDevices.flatMap(\.devices).map(\.name) == ["First"])

        firstStream.finish()
        let firstFinished = await waitUntil {
            await observeCounter.value >= 1
        }
        #expect(firstFinished)

        store.send(.onAppear)
        secondStream.yield([
            TestSupport.makeDevice(uniqueId: "light-2", name: "Second", usage: "light", data: ["on": .bool(false)])
        ])
        let didLoadSecond = await waitUntil {
            store.state.groupedDevices.flatMap(\.devices).map(\.name) == ["Second"]
        }

        #expect(didLoadSecond)
        #expect(await observeCounter.value == 2)
        #expect(store.state.groupedDevices.flatMap(\.devices).map(\.name) == ["Second"])
    }
}
