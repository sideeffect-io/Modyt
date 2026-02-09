import Testing
@testable import MoDyt

@MainActor
struct DashboardStoreTests {
    @Test
    func favoritesStreamUpdatesState() async {
        let streamBox = BufferedStreamBox<[DeviceRecord]>()
        let store = DashboardStore(
            dependencies: .init(
                observeFavoriteDevices: { streamBox.stream },
                toggleFavorite: { _ in },
                reorderFavorite: { _, _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        streamBox.yield([
            TestSupport.makeDevice(uniqueId: "a", name: "A", usage: "light", isFavorite: true),
            TestSupport.makeDevice(uniqueId: "b", name: "B", usage: "light", isFavorite: true),
            TestSupport.makeDevice(uniqueId: "c", name: "C", usage: "light", isFavorite: true)
        ])
        await settleAsyncState()

        #expect(store.state.favoriteDevices.map(\.uniqueId) == ["a", "b", "c"])
    }

    @Test
    func onAppearStartsObservationOnlyOnce() async {
        let streamBox = BufferedStreamBox<[DeviceRecord]>()
        let observeCounter = LockedCounter()
        let store = DashboardStore(
            dependencies: .init(
                observeFavoriteDevices: {
                    observeCounter.increment()
                    return streamBox.stream
                },
                toggleFavorite: { _ in },
                reorderFavorite: { _, _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        store.send(.onAppear)
        await settleAsyncState()

        #expect(observeCounter.value == 1)
    }

    @Test
    func toggleReorderAndRefreshDispatchEffects() async {
        let recorder = TestRecorder<String>()
        let store = DashboardStore(
            dependencies: .init(
                observeFavoriteDevices: {
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                toggleFavorite: { uniqueId in
                    await recorder.record("toggle:\(uniqueId)")
                },
                reorderFavorite: { sourceId, targetId in
                    await recorder.record("reorder:\(sourceId)->\(targetId)")
                },
                refreshAll: {
                    await recorder.record("refresh")
                }
            )
        )

        store.send(.toggleFavorite("device-1"))
        store.send(.reorderFavorite("device-1", "device-2"))
        store.send(.refreshRequested)
        await settleAsyncState()

        let entries = await recorder.values
        #expect(entries.contains("toggle:device-1"))
        #expect(entries.contains("reorder:device-1->device-2"))
        #expect(entries.contains("refresh"))
    }
}
