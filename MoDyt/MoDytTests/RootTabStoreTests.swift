import Testing
@testable import MoDyt

@MainActor
struct RootTabStoreTests {
    @Test
    func onStartTriggersGatewayBootstrapOnly() async {
        let bootstrapCounter = Counter()
        let appActiveRecorder = TestRecorder<Bool>()

        let store = RootTabStore(
            dependencies: makeDependencies(
                bootstrapGateway: {
                    await bootstrapCounter.increment()
                },
                setAppActive: { isActive in
                    await appActiveRecorder.record(isActive)
                }
            )
        )

        store.send(.onStart)
        await settleAsyncState()

        #expect(await bootstrapCounter.value == 1)
        #expect(await appActiveRecorder.values.isEmpty)
        #expect(store.state.isForegroundReconnectInFlight == false)
        #expect(store.state.didDisconnect == false)
    }

    @Test
    func bootstrapRunsOnceWhenOnStartRepeated() async {
        let bootstrapCounter = Counter()
        let store = RootTabStore(
            dependencies: makeDependencies(
                bootstrapGateway: {
                    await bootstrapCounter.increment()
                }
            )
        )

        store.send(.onStart)
        store.send(.onStart)
        await settleAsyncState(iterations: 16)

        #expect(await bootstrapCounter.value == 1)
    }

    @Test
    func setAppActiveFalseToTrueWhenConnectionDeadTriggersRenewConnection() async {
        let foregroundRecoveryCounter = Counter()
        let store = RootTabStore(
            dependencies: makeDependencies(
                runForegroundRecovery: { report in
                    await foregroundRecoveryCounter.increment()
                    report(.reconnecting)
                    report(.reconnected)
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))
        await settleAsyncState(iterations: 16)

        #expect(await foregroundRecoveryCounter.value == 1)
    }

    @Test
    func setAppActiveFalseToTrueWhenConnectionAliveSkipsRenewConnection() async {
        let phaseRecorder = TestRecorder<RootTabForegroundRecoveryPhase>()
        let appActiveRecorder = TestRecorder<Bool>()
        let store = RootTabStore(
            dependencies: makeDependencies(
                setAppActive: { isActive in
                    await appActiveRecorder.record(isActive)
                },
                runForegroundRecovery: { report in
                    await phaseRecorder.record(.alive)
                    report(.alive)
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))
        await settleAsyncState(iterations: 16)

        #expect(await phaseRecorder.values == [.alive])
        #expect(await appActiveRecorder.values == [false, true])
        #expect(store.state.isForegroundReconnectInFlight == false)
    }

    @Test
    func renewSuccessSetsActiveAndRestartsBootstrap() async {
        let bootstrapCounter = Counter()
        let appActiveRecorder = TestRecorder<Bool>()
        let store = RootTabStore(
            dependencies: makeDependencies(
                bootstrapGateway: {
                    await bootstrapCounter.increment()
                },
                setAppActive: { isActive in
                    await appActiveRecorder.record(isActive)
                },
                runForegroundRecovery: { report in
                    report(.reconnecting)
                    report(.reconnected)
                }
            )
        )

        store.send(.onStart)
        await settleAsyncState(iterations: 16)
        store.send(.setAppActive(false))
        store.send(.setAppActive(true))
        await settleAsyncState(iterations: 24)

        #expect(await bootstrapCounter.value == 2)
        #expect(await appActiveRecorder.values == [false, true])
        #expect(store.state.isForegroundReconnectInFlight == false)
    }

    @Test
    func renewFailureRequestsDisconnect() async {
        let disconnectCounter = Counter()
        let store = RootTabStore(
            dependencies: makeDependencies(
                runForegroundRecovery: { report in
                    report(.reconnecting)
                    report(.failed)
                },
                requestDisconnect: {
                    await disconnectCounter.increment()
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))
        await settleAsyncState(iterations: 16)

        #expect(await disconnectCounter.value == 1)
        #expect(store.state.isForegroundReconnectInFlight == false)
        #expect(store.state.didDisconnect)
    }

    @Test
    func renewCompletionIgnoredWhenStateWentInactive() async {
        let gate = ForegroundRecoveryGate()
        let recorder = TestRecorder<Bool>()
        let disconnectCounter = Counter()
        let store = RootTabStore(
            dependencies: makeDependencies(
                setAppActive: { isActive in
                    await recorder.record(isActive)
                },
                runForegroundRecovery: { report in
                    report(.reconnecting)
                    report(await gate.waitForNextPhase())
                },
                requestDisconnect: {
                    await disconnectCounter.increment()
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))
        await settleAsyncState(iterations: 16)
        #expect(store.state.isForegroundReconnectInFlight)
        #expect(await gate.callCount == 1)
        store.send(.setAppActive(false))
        await settleAsyncState(iterations: 8)
        #expect(store.state.isForegroundReconnectInFlight == false)
        await gate.resume(.failed)
        await settleAsyncState(iterations: 16)

        #expect(store.state.isAppActive == false)
        #expect(await disconnectCounter.value == 0)
        #expect(await recorder.values == [false, false])
        #expect(store.state.isForegroundReconnectInFlight == false)
        #expect(store.state.didDisconnect == false)
    }

    private func makeDependencies(
        bootstrapGateway: @escaping @Sendable () async -> Void = {},
        setAppActive: @escaping @Sendable (Bool) async -> Void = { _ in },
        runForegroundRecovery: @escaping @Sendable (
            @escaping @MainActor (RootTabForegroundRecoveryPhase) -> Void
        ) async -> Void = { _ in },
        requestDisconnect: @escaping @Sendable () async -> Void = {}
    ) -> RootTabStore.Dependencies {
        RootTabStore.Dependencies(
            bootstrapGateway: bootstrapGateway,
            setAppActive: setAppActive,
            runForegroundRecovery: runForegroundRecovery,
            requestDisconnect: requestDisconnect
        )
    }
}

private actor ForegroundRecoveryGate {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<RootTabForegroundRecoveryPhase, Never>?

    func waitForNextPhase() async -> RootTabForegroundRecoveryPhase {
        callCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(_ value: RootTabForegroundRecoveryPhase) {
        continuation?.resume(returning: value)
        continuation = nil
    }
}
