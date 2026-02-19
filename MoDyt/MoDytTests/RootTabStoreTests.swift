import Testing
@testable import MoDyt

@MainActor
struct RootTabStoreTests {
    @Test
    func onStartTriggersGatewayBootstrap() async {
        let bootstrapCounter = Counter()
        let appActiveRecorder = TestRecorder<Bool>()

        let store = RootTabStore(
            dependencies: makeDependencies(
                bootstrapGateway: {
                    await bootstrapCounter.increment()
                    return .completed
                },
                setAppActive: { isActive in
                    await appActiveRecorder.record(isActive)
                }
            )
        )

        store.send(.onStart)

        let didStart = await waitUntil {
            await bootstrapCounter.value == 1
        }
        #expect(didStart)
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
                    return .completed
                }
            )
        )

        store.send(.onStart)
        store.send(.onStart)

        let didBootstrapOnce = await waitUntil {
            await bootstrapCounter.value == 1
        }
        #expect(didBootstrapOnce)
        #expect(await bootstrapCounter.value == 1)
    }

    @Test
    func setAppActiveFalseToTrueWhenConnectionDeadTriggersRenewConnection() async {
        let foregroundRecoveryCounter = Counter()
        let store = RootTabStore(
            dependencies: makeDependencies(
                runForegroundRecovery: {
                    await foregroundRecoveryCounter.increment()
                    return .reconnected
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))

        let didRecover = await waitUntil {
            await foregroundRecoveryCounter.value == 1
        }
        #expect(didRecover)
        #expect(await foregroundRecoveryCounter.value == 1)
    }

    @Test
    func setAppActiveFalseToTrueWhenConnectionAliveSkipsRenewConnection() async {
        let foregroundRecoveryCounter = Counter()
        let appActiveRecorder = TestRecorder<Bool>()
        let store = RootTabStore(
            dependencies: makeDependencies(
                setAppActive: { isActive in
                    await appActiveRecorder.record(isActive)
                },
                runForegroundRecovery: {
                    await foregroundRecoveryCounter.increment()
                    return .alive
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))

        let didSetInactiveThenActive = await waitUntil {
            await appActiveRecorder.values == [false, true]
        }
        #expect(didSetInactiveThenActive)
        #expect(await foregroundRecoveryCounter.value == 1)
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
                    return .completed
                },
                setAppActive: { isActive in
                    await appActiveRecorder.record(isActive)
                },
                runForegroundRecovery: {
                    .reconnected
                }
            )
        )

        store.send(.onStart)
        let didStart = await waitUntil {
            await bootstrapCounter.value == 1
        }
        #expect(didStart)

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))

        let didRestart = await waitUntil {
            let bootstrapCalls = await bootstrapCounter.value
            let appActiveValues = await appActiveRecorder.values
            return bootstrapCalls == 2
                && appActiveValues == [false, true]
        }

        #expect(didRestart)
        #expect(await bootstrapCounter.value == 2)
        #expect(await appActiveRecorder.values == [false, true])
        #expect(store.state.isForegroundReconnectInFlight == false)
    }

    @Test
    func renewFailureRequestsDisconnect() async {
        let disconnectCounter = Counter()
        let store = RootTabStore(
            dependencies: makeDependencies(
                runForegroundRecovery: { .failed },
                requestDisconnect: {
                    await disconnectCounter.increment()
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))

        let didDisconnect = await waitUntil {
            await disconnectCounter.value == 1 && store.state.didDisconnect
        }
        #expect(didDisconnect)
        #expect(await disconnectCounter.value == 1)
        #expect(store.state.isForegroundReconnectInFlight == false)
        #expect(store.state.didDisconnect)
    }

    @Test
    func renewCompletionIgnoredWhenStateWentInactive() async {
        let gate = ForegroundRecoveryGate()
        let appActiveRecorder = TestRecorder<Bool>()
        let disconnectCounter = Counter()
        let store = RootTabStore(
            dependencies: makeDependencies(
                setAppActive: { isActive in
                    await appActiveRecorder.record(isActive)
                },
                runForegroundRecovery: {
                    await gate.waitForNextResult()
                },
                requestDisconnect: {
                    await disconnectCounter.increment()
                }
            )
        )

        store.send(.setAppActive(false))
        store.send(.setAppActive(true))

        let didEnterRecovery = await waitUntil {
            let callCount = await gate.callCount
            return callCount == 1 && store.state.isForegroundReconnectInFlight
        }
        #expect(didEnterRecovery)
        #expect(await gate.callCount == 1)

        store.send(.setAppActive(false))
        let didClearRecoveryFlag = await waitUntil {
            store.state.isForegroundReconnectInFlight == false
        }
        #expect(didClearRecoveryFlag)

        await gate.resume(.failed)
        let didKeepInactiveState = await waitUntil {
            await appActiveRecorder.values == [false, false]
        }
        #expect(didKeepInactiveState)
        #expect(store.state.isAppActive == false)
        #expect(await disconnectCounter.value == 0)
        #expect(await appActiveRecorder.values == [false, false])
        #expect(store.state.isForegroundReconnectInFlight == false)
        #expect(store.state.didDisconnect == false)
    }

    @Test
    func initialLoadStaysBlockedUntilBootstrapReturnsCompleted() async {
        let gate = BootstrapGate()
        let store = RootTabStore(
            dependencies: makeDependencies(
                bootstrapGateway: {
                    await gate.waitForNextResult()
                }
            )
        )

        store.send(.onStart)
        let didStartBootstrap = await waitUntil {
            await gate.callCount == 1
        }
        #expect(didStartBootstrap)
        #expect(store.state.isInitialLoadBlocking == true)

        await gate.resume(.completed)
        let didUnblock = await waitUntil {
            store.state.isInitialLoadBlocking == false
        }
        #expect(didUnblock)
        #expect(store.state.initialLoad.errorMessage == nil)
    }

    @Test
    func firstLaunchBootstrapFailureStaysBlockedAndRetryRestartsBootstrap() async {
        let gate = BootstrapGate()
        let store = RootTabStore(
            dependencies: makeDependencies(
                bootstrapGateway: {
                    await gate.waitForNextResult()
                }
            )
        )

        store.send(.onStart)
        let didRunFirstBootstrap = await waitUntil {
            await gate.callCount == 1
        }
        #expect(didRunFirstBootstrap)

        await gate.resume(.failed("network down"))
        let didReportFailure = await waitUntil {
            store.state.initialLoad.errorMessage == "network down"
        }
        #expect(didReportFailure)
        #expect(store.state.isInitialLoadBlocking == true)
        #expect(store.state.initialLoad.errorMessage == "network down")

        store.send(.retryInitialLoad)
        let didStartRetryBootstrap = await waitUntil {
            await gate.callCount == 2
        }
        #expect(didStartRetryBootstrap)
        #expect(store.state.initialLoad.errorMessage == nil)
        #expect(store.state.isInitialLoadBlocking == true)

        await gate.resume(.completed)
        let didUnblock = await waitUntil {
            store.state.isInitialLoadBlocking == false
        }
        #expect(didUnblock)
        #expect(store.state.initialLoad.errorMessage == nil)
    }

    private func makeDependencies(
        bootstrapGateway: @escaping @Sendable () async -> RootTabBootstrapResult = { .completed },
        setAppActive: @escaping @Sendable (Bool) async -> Void = { _ in },
        runForegroundRecovery: @escaping @Sendable () async -> RootTabForegroundRecoveryResult = { .alive },
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
    private var continuation: CheckedContinuation<RootTabForegroundRecoveryResult, Never>?

    func waitForNextResult() async -> RootTabForegroundRecoveryResult {
        callCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(_ result: RootTabForegroundRecoveryResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}

private actor BootstrapGate {
    private(set) var callCount = 0
    private var continuation: CheckedContinuation<RootTabBootstrapResult, Never>?

    func waitForNextResult() async -> RootTabBootstrapResult {
        callCount += 1
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(_ result: RootTabBootstrapResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
