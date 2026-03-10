import Testing
@testable import MoDyt

struct DevicesStoreReducerTests {
    struct TransitionCase: Sendable {
        let initial: DevicesState
        let event: DevicesEvent
        let expected: DevicesState
        let expectedEffects: [DevicesEffect]
    }

    private static let device = makeTestDevice(
        identifier: .init(deviceId: 10, endpointId: 1),
        name: "Kitchen Light"
    )
    private static let sections = [
        makeTestRepositoryDeviceSection(usage: .light, items: [device])
    ]
    private static let favoriteID = DeviceIdentifier(deviceId: 42, endpointId: 1)

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        var stateMachine = DevicesStore.StateMachine(state: transition.initial)
        let effects = stateMachine.reduce(transition.event)

        #expect(stateMachine.state == transition.expected)
        #expect(effects == transition.expectedEffects)
    }

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .initial,
            event: .onAppear,
            expected: .initial,
            expectedEffects: [.startObservingDevices]
        ),
        .init(
            initial: .initial,
            event: .devicesUpdated(sections),
            expected: DevicesState(groupedDevices: sections),
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
            event: .toggleFavorite(favoriteID),
            expected: .initial,
            expectedEffects: [.toggleFavorite(favoriteID)]
        ),
    ]
}

@MainActor
struct DevicesStoreEffectTests {
    @Test
    func startIsIdempotentAndObservationUpdatesState() async {
        let streamBox = TestAsyncStreamBox<[RepositoryDeviceTypeSection]>()
        let observeCalls = TestCounter()
        let expected = [
            makeTestRepositoryDeviceSection(
                usage: .light,
                items: [
                    makeTestDevice(
                        identifier: .init(deviceId: 1, endpointId: 1),
                        name: "Desk Lamp"
                    )
                ]
            )
        ]
        let store = DevicesStore(
            dependencies: .init(
                observeDevices: {
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

        streamBox.yield(expected)

        #expect(await testWaitUntil {
            store.state.groupedDevices == expected
        })
    }

    @Test
    func refreshRequestedForwardsRefreshAll() async {
        let refreshCalls = TestCounter()
        let store = DevicesStore(
            dependencies: .init(
                observeDevices: { AsyncStream { $0.finish() } },
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
        let identifier = DeviceIdentifier(deviceId: 77, endpointId: 3)
        let recorder = TestRecorder<DeviceIdentifier>()
        let store = DevicesStore(
            dependencies: .init(
                observeDevices: { AsyncStream { $0.finish() } },
                toggleFavorite: { await recorder.record($0) },
                refreshAll: {}
            )
        )

        store.send(.toggleFavorite(identifier))

        #expect(await testWaitUntilAsync {
            await recorder.values() == [identifier]
        })
    }
}
