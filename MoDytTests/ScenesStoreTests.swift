import Testing
@testable import MoDyt

struct ScenesStoreReducerTests {
    struct TransitionCase: Sendable {
        let initial: ScenesState
        let event: ScenesEvent
        let expected: ScenesState
        let expectedEffects: [ScenesEffect]
    }

    private static let scenes = [
        makeTestScene(id: "1", name: "Morning")
    ]

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        let transitionResult = ScenesStore.StateMachine.reduce(
            transition.initial,
            transition.event
        )

        #expect(transitionResult.state == transition.expected)
        #expect(transitionResult.effects == transition.expectedEffects)
    }

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .initial,
            event: .onAppear,
            expected: .initial,
            expectedEffects: [.startObservingScenes]
        ),
        .init(
            initial: .initial,
            event: .scenesObserved(scenes),
            expected: ScenesState(scenes: scenes),
            expectedEffects: []
        ),
        .init(
            initial: .initial,
            event: .refreshRequested,
            expected: .initial,
            expectedEffects: [.refreshAll]
        ),
        .init(
            initial: .initial,
            event: .toggleFavorite("scene-1"),
            expected: .initial,
            expectedEffects: [.toggleFavorite("scene-1")]
        ),
    ]
}

@MainActor
struct ScenesStoreEffectTests {
    @Test
    func startIsIdempotentAndObservationSortsScenesByName() async {
        let streamBox = TestAsyncStreamBox<[Scene]>()
        let observeCalls = TestCounter()
        let expected = [
            makeTestScene(id: "2", name: "Alpha"),
            makeTestScene(id: "1", name: "Zeta"),
        ]
        let store = ScenesStore(
            observeScenes: .init(
                observeScenes: {
                    await observeCalls.increment()
                    return streamBox.stream
                }
            ),
            toggleFavorite: .init(
                toggleFavorite: { _ in }
            ),
            refreshAll: .init(
                refreshAll: {}
            )
        )

        store.start()
        store.start()

        #expect(await testWaitUntilAsync {
            await observeCalls.value() == 1
        })

        streamBox.yield([
            makeTestScene(id: "1", name: "Zeta"),
            makeTestScene(id: "2", name: "Alpha"),
        ])

        #expect(await testWaitUntil {
            store.state.scenes == expected
        })
    }

    @Test
    func refreshRequestedForwardsRefreshAll() async {
        let refreshCalls = TestCounter()
        let store = ScenesStore(
            observeScenes: .init(
                observeScenes: { AsyncStream { $0.finish() } }
            ),
            toggleFavorite: .init(
                toggleFavorite: { _ in }
            ),
            refreshAll: .init(
                refreshAll: { await refreshCalls.increment() }
            )
        )

        store.send(.refreshRequested)

        #expect(await testWaitUntilAsync {
            await refreshCalls.value() == 1
        })
    }

    @Test
    func toggleFavoriteForwardsIdentifier() async {
        let recorder = TestRecorder<String>()
        let store = ScenesStore(
            observeScenes: .init(
                observeScenes: { AsyncStream { $0.finish() } }
            ),
            toggleFavorite: .init(
                toggleFavorite: { await recorder.record($0) }
            ),
            refreshAll: .init(
                refreshAll: {}
            )
        )

        store.send(.toggleFavorite("scene-42"))

        #expect(await testWaitUntilAsync {
            await recorder.values() == ["scene-42"]
        })
    }
}
