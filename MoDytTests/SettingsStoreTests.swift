import Testing
@testable import MoDyt

struct SettingsStoreReducerTests {
    @Test
    func disconnectTappedStartsDisconnectAndRequestsEffect() {
        let transition = SettingsStore.StateMachine.reduce(.initial, .disconnectTapped)

        #expect(transition.state.isDisconnecting)
        #expect(transition.state.didDisconnect == false)
        #expect(transition.state.errorMessage == nil)
        #expect(transition.effects == [.requestDisconnect])
    }

    @Test
    func secondDisconnectTapWhileInFlightIsIgnored() {
        let initial = SettingsState(
            isDisconnecting: true,
            didDisconnect: false,
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
                didDisconnect: false,
                errorMessage: "stale"
            ),
            .disconnectFinished
        )

        #expect(transition.state == .init(
            isDisconnecting: false,
            didDisconnect: true,
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
    }
}
