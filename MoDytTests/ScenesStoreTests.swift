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
        var stateMachine = ScenesStore.StateMachine(state: transition.initial)
        let effects = stateMachine.reduce(transition.event)

        #expect(stateMachine.state == transition.expected)
        #expect(effects == transition.expectedEffects)
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
            event: .scenesUpdated(scenes),
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
            dependencies: .init(
                observeScenes: {
                    await observeCalls.increment()
                    return streamBox.stream
                },
                toggleFavorite: { _ in },
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
            dependencies: .init(
                observeScenes: { AsyncStream { $0.finish() } },
                toggleFavorite: { _ in },
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
            dependencies: .init(
                observeScenes: { AsyncStream { $0.finish() } },
                toggleFavorite: { await recorder.record($0) },
                refreshAll: {}
            )
        )

        store.send(.toggleFavorite("scene-42"))

        #expect(await testWaitUntilAsync {
            await recorder.values() == ["scene-42"]
        })
    }
}
