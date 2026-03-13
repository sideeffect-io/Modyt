import Testing
@testable import MoDyt

struct SettingsStoreReducerTests {
    @Test
    func connectionRouteRefreshStartsLoadingAndRequestsEffect() {
        let transition = SettingsStore.StateMachine.reduce(.initial, .connectionRouteRefreshRequested)

        #expect(transition.state.isRefreshingConnectionRoute)
        #expect(transition.state.connectionRoute == .unavailable)
        #expect(transition.effects == [.refreshConnectionRoute])
    }

    @Test
    func secondConnectionRouteRefreshWhileInFlightIsIgnored() {
        let initial = SettingsState(
            isDisconnecting: false,
            isRefreshingConnectionRoute: true,
            didDisconnect: false,
            connectionRoute: .local(host: "192.168.1.20"),
            errorMessage: nil
        )
        let transition = SettingsStore.StateMachine.reduce(initial, .connectionRouteRefreshRequested)

        #expect(transition.state == initial)
        #expect(transition.effects.isEmpty)
    }

    @Test
    func connectionRouteLoadedStopsLoadingAndStoresRoute() {
        let transition = SettingsStore.StateMachine.reduce(
            .init(
                isDisconnecting: false,
                isRefreshingConnectionRoute: true,
                didDisconnect: false,
                connectionRoute: .unavailable,
                errorMessage: nil
            ),
            .connectionRouteLoaded(.remote(host: "mediation.tydom.com"))
        )

        #expect(transition.state == .init(
            isDisconnecting: false,
            isRefreshingConnectionRoute: false,
            didDisconnect: false,
            connectionRoute: .remote(host: "mediation.tydom.com"),
            errorMessage: nil
        ))
        #expect(transition.effects.isEmpty)
    }

    @Test
    func disconnectTappedStartsDisconnectAndRequestsEffect() {
        let transition = SettingsStore.StateMachine.reduce(.initial, .disconnectTapped)

        #expect(transition.state.isDisconnecting)
        #expect(transition.state.isRefreshingConnectionRoute == false)
        #expect(transition.state.didDisconnect == false)
        #expect(transition.state.connectionRoute == .unavailable)
        #expect(transition.state.errorMessage == nil)
        #expect(transition.effects == [.requestDisconnect])
    }

    @Test
    func secondDisconnectTapWhileInFlightIsIgnored() {
        let initial = SettingsState(
            isDisconnecting: true,
            isRefreshingConnectionRoute: false,
            didDisconnect: false,
            connectionRoute: .local(host: "192.168.1.20"),
            errorMessage: nil
        )
        let transition = SettingsStore.StateMachine.reduce(initial, .disconnectTapped)

        #expect(transition.state == initial)
        #expect(transition.effects.isEmpty)
    }

    @Test
    func disconnectFinishedResetsStateAndMarksSuccess() {
        let transition = SettingsStore.StateMachine.reduce(
            .init(
                isDisconnecting: true,
                isRefreshingConnectionRoute: true,
                didDisconnect: false,
                connectionRoute: .local(host: "192.168.1.20"),
                errorMessage: "stale"
            ),
            .disconnectFinished
        )

        #expect(transition.state == .init(
            isDisconnecting: false,
            isRefreshingConnectionRoute: false,
            didDisconnect: true,
            connectionRoute: .unavailable,
            errorMessage: nil
        ))
        #expect(transition.effects.isEmpty)
    }
}

@MainActor
struct SettingsStoreEffectTests {
    @Test
    func disconnectRunsOnceAndCompletes() async {
        let requestCalls = TestCounter()
        let gate = TestAsyncStreamBox<Void>()
        let store = SettingsStore(
            refreshConnectionRoute: .init(
                readConnectionRoute: { .unavailable }
            ),
            requestDisconnect: .init(
                requestDisconnect: {
                    await requestCalls.increment()
                    var iterator = gate.stream.makeAsyncIterator()
                    _ = await iterator.next()
                }
            )
        )

        store.send(.disconnectTapped)

        #expect(await testWaitUntil {
            store.state.isDisconnecting
        })

        store.send(.disconnectTapped)

        #expect(await testWaitUntilAsync {
            await requestCalls.value() == 1
        })

        gate.yield(())
        gate.finish()

        #expect(await testWaitUntil {
            store.state.didDisconnect && store.state.isDisconnecting == false
        })
        #expect(store.state.connectionRoute == .unavailable)
    }

    @Test
    func connectionRouteRefreshRunsOnceAndStoresLatestSnapshot() async {
        let refreshCalls = TestCounter()
        let gate = TestAsyncStreamBox<SettingsConnectionRoute>()
        let store = SettingsStore(
            refreshConnectionRoute: .init(
                readConnectionRoute: {
                    await refreshCalls.increment()
                    var iterator = gate.stream.makeAsyncIterator()
                    return await iterator.next() ?? .unavailable
                }
            ),
            requestDisconnect: .init(
                requestDisconnect: {}
            )
        )

        store.send(.connectionRouteRefreshRequested)

        #expect(await testWaitUntil {
            store.state.isRefreshingConnectionRoute
        })

        store.send(.connectionRouteRefreshRequested)

        #expect(await testWaitUntilAsync {
            await refreshCalls.value() == 1
        })

        gate.yield(.local(host: "192.168.1.20"))
        gate.finish()

        #expect(await testWaitUntil {
            store.state.isRefreshingConnectionRoute == false &&
            store.state.connectionRoute == .local(host: "192.168.1.20")
        })
    }
}
