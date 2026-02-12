import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct ScenesStoreTests {
    @Test
    func updatesStateFromIncomingScenes() async {
        let streamBox = BufferedStreamBox<[SceneRecord]>()
        let store = ScenesStore(
            dependencies: .init(
                observeScenes: { streamBox.stream },
                toggleFavorite: { _ in },
                refreshAll: {}
            )
        )

        store.send(.onAppear)
        streamBox.yield([
            makeScene(uniqueId: "scene_2", sceneId: 2, name: "Evening"),
            makeScene(uniqueId: "scene_1", sceneId: 1, name: "Morning")
        ])
        await settleAsyncState()
        streamBox.finish()

        #expect(store.state.scenes.map(\.name) == ["Evening", "Morning"])
    }

    @Test
    func toggleAndRefreshDispatchEffects() async {
        let recorder = TestRecorder<String>()
        let store = ScenesStore(
            dependencies: .init(
                observeScenes: {
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

        store.send(.toggleFavorite("scene_10"))
        store.send(.refreshRequested)
        await settleAsyncState()

        let entries = await recorder.values
        #expect(entries.contains("toggle:scene_10"))
        #expect(entries.contains("refresh"))
    }

    @Test
    func onAppearStartsObservationOnlyOnce() async {
        let streamBox = BufferedStreamBox<[SceneRecord]>()
        let observeCounter = Counter()

        let store = ScenesStore(
            dependencies: .init(
                observeScenes: {
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

    private func makeScene(uniqueId: String, sceneId: Int, name: String) -> SceneRecord {
        SceneRecord(
            uniqueId: uniqueId,
            sceneId: sceneId,
            name: name,
            type: "NORMAL",
            picto: "scene",
            ruleId: nil,
            payload: [:],
            isFavorite: false,
            favoriteOrder: nil,
            dashboardOrder: nil,
            updatedAt: Date()
        )
    }
}
