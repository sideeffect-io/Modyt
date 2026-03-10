import Testing
@testable import MoDyt

struct SettingsStoreReducerTests {
    @Test
    func disconnectTappedStartsDisconnectAndRequestsEffect() {
        var stateMachine = SettingsStore.StateMachine(state: .initial)

        let effects = stateMachine.reduce(.disconnectTapped)

        #expect(stateMachine.state.isDisconnecting)
        #expect(stateMachine.state.didDisconnect == false)
        #expect(stateMachine.state.errorMessage == nil)
        #expect(effects == [.requestDisconnect])
    }

    @Test
    func secondDisconnectTapWhileInFlightIsIgnored() {
        var stateMachine = SettingsStore.StateMachine(state: .init(
            isDisconnecting: true,
            didDisconnect: false,
            errorMessage: nil
        ))

        let effects = stateMachine.reduce(.disconnectTapped)

        #expect(stateMachine.state == .init(
            isDisconnecting: true,
            didDisconnect: false,
            errorMessage: nil
        ))
        #expect(effects.isEmpty)
    }

    @Test
    func disconnectFinishedResetsStateAndMarksSuccess() {
        var stateMachine = SettingsStore.StateMachine(state: .init(
            isDisconnecting: true,
            didDisconnect: false,
            errorMessage: "stale"
        ))

        let effects = stateMachine.reduce(.disconnectFinished)

        #expect(stateMachine.state == .init(
            isDisconnecting: false,
            didDisconnect: true,
            errorMessage: nil
        ))
        #expect(effects.isEmpty)
    }
}

@MainActor
struct SettingsStoreEffectTests {
    @Test
    func disconnectRunsOnceAndCompletes() async {
        let requestCalls = TestCounter()
        let gate = TestAsyncStreamBox<Void>()
        let store = SettingsStore(
            dependencies: .init(
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
