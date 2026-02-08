import Testing
@testable import MoDyt

@MainActor
struct DashboardStoreTests {
    @Test
    func favoritesStreamUpdatesState() async {
        let streamBox = BufferedStreamBox<[String]>()
        let store = DashboardStore(
            dependencies: .init(
                observeFavoriteIDs: { streamBox.stream },
                toggleFavorite: { _ in },
                reorderFavorite: { _, _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        streamBox.yield(["a", "b", "c"])
        await settleAsyncState()

        #expect(store.state.favoriteIDs == ["a", "b", "c"])
    }

    @Test
    func onAppearStartsObservationOnlyOnce() async {
        let streamBox = BufferedStreamBox<[String]>()
        let observeCounter = LockedCounter()
        let store = DashboardStore(
            dependencies: .init(
                observeFavoriteIDs: {
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
                observeFavoriteIDs: {
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
