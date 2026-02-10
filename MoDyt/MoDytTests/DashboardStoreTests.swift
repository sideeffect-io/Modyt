import Testing
@testable import MoDyt

@MainActor
struct DashboardStoreTests {
    @Test
    func favoritesStreamUpdatesState() async {
        let streamBox = BufferedStreamBox<[DashboardDeviceDescription]>()
        let store = DashboardStore(
            dependencies: .init(
                observeFavoriteDevices: { streamBox.stream },
                reorderFavorite: { _, _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        streamBox.yield([
            DashboardDeviceDescription(uniqueId: "a", name: "A", usage: "light"),
            DashboardDeviceDescription(uniqueId: "b", name: "B", usage: "light"),
            DashboardDeviceDescription(uniqueId: "c", name: "C", usage: "light")
        ])
        await settleAsyncState()

        #expect(store.state.favoriteDevices.map(\.uniqueId) == ["a", "b", "c"])
    }

    @Test
    func onAppearStartsObservationOnlyOnce() async {
        let streamBox = BufferedStreamBox<[DashboardDeviceDescription]>()
        let observeCounter = LockedCounter()
        let store = DashboardStore(
            dependencies: .init(
                observeFavoriteDevices: {
                    observeCounter.increment()
                    return streamBox.stream
                },
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
    func reorderAndRefreshDispatchEffects() async {
        let recorder = TestRecorder<String>()
        let store = DashboardStore(
            dependencies: .init(
                observeFavoriteDevices: {
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                reorderFavorite: { sourceId, targetId in
                    await recorder.record("reorder:\(sourceId)->\(targetId)")
                },
                refreshAll: {
                    await recorder.record("refresh")
                }
            )
        )

        store.send(.reorderFavorite("device-1", "device-2"))
        store.send(.refreshRequested)
        await settleAsyncState()

        let entries = await recorder.values
        #expect(entries.contains("reorder:device-1->device-2"))
        #expect(entries.contains("refresh"))
    }
}
