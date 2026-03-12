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
        let transitionResult = DevicesStore.StateMachine.reduce(
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
            expectedEffects: [.startObservingDevices]
        ),
        .init(
            initial: .initial,
            event: .devicesObserved([device]),
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
        let streamBox = TestAsyncStreamBox<[Device]>()
        let observeCalls = TestCounter()
        let expectedDevice = makeTestDevice(
            identifier: .init(deviceId: 1, endpointId: 1),
            name: "Desk Lamp"
        )
        let expected = [
            makeTestRepositoryDeviceSection(usage: Usage.light, items: [expectedDevice])
        ]
        let store = DevicesStore(
            observeDevices: .init(
                observeDevices: {
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

        streamBox.yield([expectedDevice])

        #expect(await testWaitUntil {
            store.state.groupedDevices == expected
        })
    }

    @Test
    func refreshRequestedForwardsRefreshAll() async {
        let refreshCalls = TestCounter()
        let store = DevicesStore(
            observeDevices: .init(
                observeDevices: { AsyncStream { $0.finish() } }
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
        let identifier = DeviceIdentifier(deviceId: 77, endpointId: 3)
        let recorder = TestRecorder<DeviceIdentifier>()
        let store = DevicesStore(
            observeDevices: .init(
                observeDevices: { AsyncStream { $0.finish() } }
            ),
            toggleFavorite: .init(
                toggleFavorite: { await recorder.record($0) }
            ),
            refreshAll: .init(
                refreshAll: {}
            )
        )

        store.send(.toggleFavorite(identifier))

        #expect(await testWaitUntilAsync {
            await recorder.values() == [identifier]
        })
    }
}
