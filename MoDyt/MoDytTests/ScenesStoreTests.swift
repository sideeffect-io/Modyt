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
        let didUpdate = await waitUntil {
            store.state.scenes.map(\.name) == ["Evening", "Morning"]
        }
        streamBox.finish()

        #expect(didUpdate)
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
        let didDispatch = await waitUntil {
            let entries = await recorder.values
            return entries.contains("toggle:scene_10")
                && entries.contains("refresh")
        }

        #expect(didDispatch)
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
        let observedOnce = await waitUntil {
            await observeCounter.value == 1
        }

        #expect(observedOnce)
        #expect(await observeCounter.value == 1)
    }

    @Test
    func observationRestartsAfterStreamCompletion() async {
        let firstStream = BufferedStreamBox<[SceneRecord]>()
        let secondStream = BufferedStreamBox<[SceneRecord]>()
        let observeCounter = Counter()

        let store = ScenesStore(
            dependencies: .init(
                observeScenes: {
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
            makeScene(uniqueId: "scene_1", sceneId: 1, name: "First")
        ])
        let didLoadFirst = await waitUntil {
            store.state.scenes.map(\.name) == ["First"]
        }
        #expect(didLoadFirst)
        #expect(store.state.scenes.map(\.name) == ["First"])

        firstStream.finish()
        let firstFinished = await waitUntil {
            await observeCounter.value >= 1
        }
        #expect(firstFinished)

        store.send(.onAppear)
        secondStream.yield([
            makeScene(uniqueId: "scene_2", sceneId: 2, name: "Second")
        ])
        let didLoadSecond = await waitUntil {
            store.state.scenes.map(\.name) == ["Second"]
        }

        #expect(didLoadSecond)
        #expect(await observeCounter.value == 2)
        #expect(store.state.scenes.map(\.name) == ["Second"])
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
