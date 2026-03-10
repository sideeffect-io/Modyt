import Testing
@testable import MoDyt

struct GroupsStoreReducerTests {
    struct TransitionCase: Sendable {
        let initial: GroupsState
        let event: GroupsEvent
        let expected: GroupsState
        let expectedEffects: [GroupsEffect]
    }

    private static let groups = [
        makeTestGroup(id: "1", name: "Kitchen")
    ]

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        var stateMachine = GroupsStore.StateMachine(state: transition.initial)
        let effects = stateMachine.reduce(transition.event)

        #expect(stateMachine.state == transition.expected)
        #expect(effects == transition.expectedEffects)
    }

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .initial,
            event: .onAppear,
            expected: .initial,
            expectedEffects: [.startObservingGroups]
        ),
        .init(
            initial: .initial,
            event: .groupsUpdated(groups),
            expected: GroupsState(groups: groups),
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
            event: .toggleFavorite("group-1"),
            expected: .initial,
            expectedEffects: [.toggleFavorite("group-1")]
        ),
    ]
}

@MainActor
struct GroupsStoreEffectTests {
    @Test
    func startIsIdempotentAndObservationFiltersAndSortsGroups() async {
        let streamBox = TestAsyncStreamBox<[Group]>()
        let observeCalls = TestCounter()
        let expected = [
            makeTestGroup(id: "2", name: "Alpha", isGroupUser: true),
            makeTestGroup(id: "1", name: "Zeta", isGroupUser: true),
        ]
        let store = GroupsStore(
            dependencies: .init(
                observeGroups: {
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
            makeTestGroup(id: "1", name: "Zeta", isGroupUser: true),
            makeTestGroup(id: "3", name: "Ignored", isGroupUser: false),
            makeTestGroup(id: "2", name: "Alpha", isGroupUser: true),
        ])

        #expect(await testWaitUntil {
            store.state.groups == expected
        })
    }

    @Test
    func refreshRequestedForwardsRefreshAll() async {
        let refreshCalls = TestCounter()
        let store = GroupsStore(
            dependencies: .init(
                observeGroups: { AsyncStream { $0.finish() } },
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
        let store = GroupsStore(
            dependencies: .init(
                observeGroups: { AsyncStream { $0.finish() } },
                toggleFavorite: { await recorder.record($0) },
                refreshAll: {}
            )
        )

        store.send(.toggleFavorite("group-42"))

        #expect(await testWaitUntilAsync {
            await recorder.values() == ["group-42"]
        })
    }
}
