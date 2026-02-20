import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct ShutterStoreTests {
    private func positions(
        actual: Int,
        target: Int,
        trust: TargetTrust = .trusted
    ) -> Positions {
        Positions(actual: actual, target: target, targetTrust: trust)
    }

    @Test
    func reducer_idleReceivedEqualTransitionsToIdleWithoutEffects() {
        let state = ShuttersState.idle(positions(actual: 100, target: 25))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: 50, target: 50)
        )

        #expect(next == .idle(positions(actual: 50, target: 50)))
        #expect(effects.isEmpty)
    }

    @Test
    func reducer_idleReceivedDifferentWithChangedTargetTransitionsToMovingTrustedAndStartsTimer() {
        let state = ShuttersState.idle(positions(actual: 100, target: 100))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: 25, target: 50)
        )

        #expect(next == .moving(positions(actual: 25, target: 50)))
        #expect(effects == [.startCompletionTimer])
    }

    @Test
    func reducer_idleReceivedDifferentWithUnchangedTargetTransitionsToMovingAcknowledgedAndStartsTimer() {
        let state = ShuttersState.idle(positions(actual: 100, target: 50))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: 25, target: 50)
        )

        #expect(
            next == .moving(
                positions(
                    actual: 100,
                    target: 25,
                    trust: .acknowledged(staleStreamTarget: 50)
                )
            )
        )
        #expect(effects == [.startCompletionTimer])
    }

    @Test
    func reducer_idleSetTargetTransitionsToMovingWithOrderedEffects() {
        let state = ShuttersState.idle(positions(actual: 100, target: 100))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .setTarget(value: 50)
        )

        #expect(next == .moving(positions(actual: 100, target: 50)))
        #expect(effects == [.handleTarget(value: 50), .startCompletionTimer])
    }

    @Test
    func reducer_movingReceivedEqualTransitionsToIdleAndCancelsTimer() {
        let state = ShuttersState.moving(positions(actual: 25, target: 50))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: 50, target: 50)
        )

        #expect(next == .idle(positions(actual: 50, target: 50)))
        #expect(effects == [.cancelCompletionTimer])
    }

    @Test
    func reducer_movingAcknowledgedIgnoresStaleTargetAndResetsTimerOnActualProgress() {
        let state = ShuttersState.moving(
            positions(
                actual: 25,
                target: 25,
                trust: .acknowledged(staleStreamTarget: 50)
            )
        )

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: 50, target: 50)
        )

        #expect(
            next == .moving(
                positions(
                    actual: 50,
                    target: 25,
                    trust: .acknowledged(staleStreamTarget: 50)
                )
            )
        )
        #expect(effects == [.cancelCompletionTimer, .startCompletionTimer])
    }

    @Test
    func reducer_movingTrustedFailedToCompleteTransitionsToIdleWithoutEffects() {
        let state = ShuttersState.moving(positions(actual: 25, target: 50))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .failedToComplete
        )

        #expect(next == .idle(positions(actual: 25, target: 50)))
        #expect(effects.isEmpty)
    }

    @Test
    func reducer_movingAcknowledgedFailedToCompleteTransitionsToIdleWithSnappedTarget() {
        let state = ShuttersState.moving(
            positions(
                actual: 25,
                target: 50,
                trust: .acknowledged(staleStreamTarget: 100)
            )
        )

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .failedToComplete
        )

        #expect(next == .idle(positions(actual: 25, target: 25)))
        #expect(effects.isEmpty)
    }

    @Test
    func reducer_movingAcknowledgedReceivedStaleTargetPreservesAcknowledgedTargetAndResetsTimerOnActualProgress() {
        let state = ShuttersState.moving(
            positions(
                actual: 100,
                target: 25,
                trust: .acknowledged(staleStreamTarget: 50)
            )
        )

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: 30, target: 50)
        )

        #expect(
            next == .moving(
                positions(
                    actual: 30,
                    target: 25,
                    trust: .acknowledged(staleStreamTarget: 50)
                )
            )
        )
        #expect(effects == [.cancelCompletionTimer, .startCompletionTimer])
    }

    @Test
    func reducer_movingAcknowledgedReceivedStaleTargetAtInferredTargetTransitionsToIdleAndCancelsTimer() {
        let state = ShuttersState.moving(
            positions(
                actual: 98,
                target: 0,
                trust: .acknowledged(staleStreamTarget: 100)
            )
        )

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: 0, target: 100)
        )

        #expect(next == .idle(positions(actual: 0, target: 0)))
        #expect(effects == [.cancelCompletionTimer, .syncTargetCache(value: 0)])
    }

    @Test
    func reducer_movingAcknowledgedReceivedDifferentWithNewTargetPromotesToTrustedAndRestartsTimer() {
        let state = ShuttersState.moving(
            positions(
                actual: 100,
                target: 50,
                trust: .acknowledged(staleStreamTarget: 50)
            )
        )

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: 25, target: 75)
        )

        #expect(next == .moving(positions(actual: 25, target: 75)))
        #expect(effects == [.cancelCompletionTimer, .startCompletionTimer])
    }

    @Test
    func reducer_movingSetTargetTransitionsWithOrderedEffects() {
        let state = ShuttersState.moving(positions(actual: 25, target: 50))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .setTarget(value: 0)
        )

        #expect(next == .moving(positions(actual: 25, target: 0)))
        #expect(effects == [.handleTarget(value: 0), .cancelCompletionTimer, .startCompletionTimer])
    }

    @Test
    func observePositionsStreamDrivesReceivedValuesEvent() async {
        let streamBox = BufferedStreamBox<(actual: Int, target: Int)>()
        let store = ShutterStore(
            shutterUniqueIds: ["shutter-1"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                startCompletionTimer: { _ in Task { } }
            )
        )

        streamBox.yield((actual: 25, target: 50))
        let didMove = await waitUntil {
            store.state == .moving(positions(actual: 25, target: 50))
        }

        #expect(didMove)
        #expect(store.actualPosition == 25)
        #expect(store.targetPosition == 50)
        #expect(store.isTargetReliable)
        #expect(store.isMoving)
    }

    @Test
    func setTargetCallsSendTargetPositionWithExactIdsAndStep() async throws {
        let recorder = TestRecorder<([String], Int)>()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1", "id-2"],
            dependencies: .init(
                observePositions: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                sendTargetPosition: { ids, target in
                    await recorder.record((ids, target))
                },
                startCompletionTimer: { _ in Task { } }
            )
        )

        store.send(.setTarget(value: 75))

        let didRecord = await waitUntil {
            await recorder.values.count == 1
        }

        #expect(didRecord)
        let entries = await recorder.values
        #expect(entries.count == 1)
        let first = try #require(entries.first)
        #expect(first.0 == ["id-1", "id-2"])
        #expect(first.1 == 75)
    }

    @Test
    func movingToIdleFromStreamCancelsCompletionTimer() async {
        let streamBox = BufferedStreamBox<(actual: Int, target: Int)>()
        let timer = CompletionTimerHarness()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                startCompletionTimer: timer.start
            )
        )

        store.send(.setTarget(value: 0))
        let didStartMoving = await waitUntil {
            store.state == .moving(positions(actual: 100, target: 0))
                && timer.startCount == 1
        }
        #expect(didStartMoving)
        #expect(store.state == .moving(positions(actual: 100, target: 0)))
        #expect(timer.startCount == 1)

        streamBox.yield((actual: 0, target: 0))
        let becameIdle = await waitUntil {
            store.state == .idle(positions(actual: 0, target: 0))
        }
        let didCancelTimer = await waitUntil {
            timer.cancelCount == 1
        }

        #expect(becameIdle)
        #expect(didCancelTimer)
        #expect(timer.cancelCount == 1)
    }

    @Test
    func completionTimerCallbackSendsFailedToCompleteEvent() async {
        let timer = CompletionTimerHarness()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1"],
            dependencies: .init(
                observePositions: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                sendTargetPosition: { _, _ in },
                startCompletionTimer: timer.start
            )
        )

        store.send(.setTarget(value: 50))
        let didStartMoving = await waitUntil {
            store.state == .moving(positions(actual: 100, target: 50))
        }
        #expect(didStartMoving)
        #expect(store.state == .moving(positions(actual: 100, target: 50)))

        timer.triggerLatest()

        let becameIdleAfterFailure = await waitUntil {
            store.state == .idle(positions(actual: 100, target: 50))
        }

        #expect(becameIdleAfterFailure)
    }

    @Test
    func externalLikeMovementWithUnchangedTargetAcknowledgesTargetAndTimeoutSnapsToActual() async {
        let streamBox = BufferedStreamBox<(actual: Int, target: Int)>()
        let timer = CompletionTimerHarness()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                startCompletionTimer: timer.start
            )
        )

        streamBox.yield((actual: 25, target: 100))
        let becameMovingWithAcknowledgedTarget = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 100,
                    target: 25,
                    trust: .acknowledged(staleStreamTarget: 100)
                )
            )
                && timer.startCount == 1
        }

        #expect(becameMovingWithAcknowledgedTarget)
        #expect(store.isMoving)
        #expect(store.isTargetReliable)
        #expect(store.actualPosition == 100)
        #expect(store.targetPosition == 25)

        timer.triggerLatest()
        let becameIdleAfterTimeout = await waitUntil {
            store.state == .idle(positions(actual: 100, target: 100))
        }

        #expect(becameIdleAfterTimeout)
        #expect(store.isTargetReliable)
    }

    @Test
    func externalPseudoAckSetsTargetWithoutJumpingActualThenTracksIncomingActual() async {
        let streamBox = BufferedStreamBox<(actual: Int, target: Int)>()
        let timer = CompletionTimerHarness()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                startCompletionTimer: timer.start
            )
        )

        streamBox.yield((actual: 50, target: 50))
        let establishedBaseline = await waitUntil {
            store.state == .idle(positions(actual: 50, target: 50))
        }
        #expect(establishedBaseline)

        // Gateway pseudo-ack: actual jumps to the external target while stream target is stale.
        streamBox.yield((actual: 100, target: 50))
        let acknowledgedWithoutActualJump = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 50,
                    target: 100,
                    trust: .acknowledged(staleStreamTarget: 50)
                )
            )
        }
        #expect(acknowledgedWithoutActualJump)
        #expect(store.targetPosition == 100)
        #expect(store.actualPosition == 50)
        #expect(store.isTargetReliable)

        // Next values should drive actual tracking while stale stream target is ignored.
        streamBox.yield((actual: 51, target: 50))
        let trackedFirstActual = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 51,
                    target: 100,
                    trust: .acknowledged(staleStreamTarget: 50)
                )
            )
        }
        #expect(trackedFirstActual)

        streamBox.yield((actual: 64, target: 50))
        let trackedSecondActual = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 64,
                    target: 100,
                    trust: .acknowledged(staleStreamTarget: 50)
                )
            )
        }
        #expect(trackedSecondActual)
    }

    @Test
    func sceneLikeExternalCloseCompletesWhenInferredTargetIsReachedWithoutTimeoutTransition() async {
        let streamBox = BufferedStreamBox<(actual: Int, target: Int)>()
        let timer = CompletionTimerHarness()
        let synchronizedTargets = TestRecorder<([String], Int)>()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                syncTargetCache: { ids, target in
                    await synchronizedTargets.record((ids, target))
                },
                startCompletionTimer: timer.start
            )
        )

        // External scene pseudo-ack: first value is interpreted as inferred target.
        streamBox.yield((actual: 0, target: 100))
        let acknowledgedStart = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 100,
                    target: 0,
                    trust: .acknowledged(staleStreamTarget: 100)
                )
            )
                && timer.startCount == 1
        }
        #expect(acknowledgedStart)

        // Real movement progress should keep moving and refresh timeout.
        streamBox.yield((actual: 98, target: 100))
        let trackedProgress = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 98,
                    target: 0,
                    trust: .acknowledged(staleStreamTarget: 100)
                )
            )
                && timer.startCount == 2
                && timer.cancelCount == 1
        }
        #expect(trackedProgress)

        // When actual reaches inferred target with stale stream target, movement completes immediately.
        streamBox.yield((actual: 0, target: 100))
        let completedWithoutTimeout = await waitUntil {
            store.state == .idle(positions(actual: 0, target: 0))
        }
        let didSyncInferredTarget = await waitUntil {
            await synchronizedTargets.values.count == 1
        }
        #expect(completedWithoutTimeout)
        #expect(didSyncInferredTarget)
        let syncedEntries = await synchronizedTargets.values
        #expect(syncedEntries.count == 1)
        if let first = syncedEntries.first {
            #expect(first.0 == ["id-1"])
            #expect(first.1 == 0)
        } else {
            #expect(Bool(false))
        }
        #expect(store.isTargetReliable)
        #expect(!store.isMoving)
    }

    @Test
    func multiIdStoreDoesNotSyncInferredTargetCache() async {
        let streamBox = BufferedStreamBox<(actual: Int, target: Int)>()
        let timer = CompletionTimerHarness()
        let synchronizedTargets = TestRecorder<([String], Int)>()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1", "id-2"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                syncTargetCache: { ids, target in
                    await synchronizedTargets.record((ids, target))
                },
                startCompletionTimer: timer.start
            )
        )

        streamBox.yield((actual: 50, target: 100))
        let becameMovingWithAcknowledgedTarget = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 100,
                    target: 50,
                    trust: .acknowledged(staleStreamTarget: 100)
                )
            )
                && timer.startCount == 1
        }
        #expect(becameMovingWithAcknowledgedTarget)

        // Completion on inferred target should not write cache for aggregate stores.
        streamBox.yield((actual: 50, target: 100))
        let completed = await waitUntil {
            store.state == .idle(positions(actual: 50, target: 50))
        }
        #expect(completed)

        // Give asynchronous effects a chance to run if any were queued.
        let noSyncRecorded = await waitUntil {
            await synchronizedTargets.values.isEmpty
        }
        #expect(noSyncRecorded)
        #expect(await synchronizedTargets.values.isEmpty)
    }

    @Test
    func externalLikeMovementWhenCrossingCachedTargetKeepsAcknowledgedUntilTimeout() async {
        let streamBox = BufferedStreamBox<(actual: Int, target: Int)>()
        let timer = CompletionTimerHarness()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                startCompletionTimer: timer.start
            )
        )

        // Establish a cached trusted target at 50.
        streamBox.yield((actual: 50, target: 50))
        let establishedBaseline = await waitUntil {
            store.state == .idle(positions(actual: 50, target: 50))
        }
        #expect(establishedBaseline)

        // External move starts while target remains stale at 50.
        streamBox.yield((actual: 25, target: 50))
        let becameMovingAcknowledged = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 50,
                    target: 25,
                    trust: .acknowledged(staleStreamTarget: 50)
                )
            )
                && timer.startCount == 1
        }
        #expect(becameMovingAcknowledged)
        #expect(store.isTargetReliable)

        // Crossing the stale cached target should not re-enable target reliability.
        streamBox.yield((actual: 50, target: 50))
        let remainedMovingAcknowledged = await waitUntil {
            store.state == .moving(
                positions(
                    actual: 50,
                    target: 25,
                    trust: .acknowledged(staleStreamTarget: 50)
                )
            )
        }
        #expect(remainedMovingAcknowledged)
        #expect(store.isMoving)
        #expect(store.isTargetReliable)

        timer.triggerLatest()
        let becameIdleAfterTimeout = await waitUntil {
            store.state == .idle(positions(actual: 50, target: 50))
        }
        #expect(becameIdleAfterTimeout)
        #expect(store.isTargetReliable)
    }

    @Test
    func mappedCommandUsesDescriptorKeyAndRange() throws {
        let positionDescriptor = DeviceControlDescriptor(
            kind: .slider,
            key: "position",
            isOn: true,
            value: 1,
            range: 0...1
        )
        let positionCommand = ShutterStoreFactory.mappedCommand(
            targetPosition: 25,
            descriptor: positionDescriptor
        )
        #expect(positionCommand.key == "position")
        let positionValue = try #require(positionCommand.value.numberValue)
        #expect(abs(positionValue - 0.25) < 0.0001)

        let levelDescriptor = DeviceControlDescriptor(
            kind: .slider,
            key: "level",
            isOn: true,
            value: 100,
            range: 0...100
        )
        let levelCommand = ShutterStoreFactory.mappedCommand(
            targetPosition: 25,
            descriptor: levelDescriptor
        )
        #expect(levelCommand.key == "level")
        let levelValue = try #require(levelCommand.value.numberValue)
        #expect(abs(levelValue - 25) < 0.0001)
    }
}

private final class CompletionTimerHarness: @unchecked Sendable {
    private let lock = NSLock()
    private var rawStartCount = 0
    private var rawCancelCount = 0
    private var callbacks: [@MainActor @Sendable () -> Void] = []

    var startCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return rawStartCount
    }

    var cancelCount: Int {
        lock.lock()
        defer { lock.unlock() }
        return rawCancelCount
    }

    func start(_ callback: @escaping @MainActor @Sendable () -> Void) -> Task<Void, Never> {
        lock.lock()
        rawStartCount += 1
        callbacks.append(callback)
        lock.unlock()

        return Task { [weak self] in
            while true {
                do {
                    try await Task.sleep(for: .seconds(3600))
                } catch {
                    if Task.isCancelled {
                        self?.incrementCancelCount()
                    }
                    return
                }
            }
        }
    }

    func triggerLatest() {
        lock.lock()
        let callback = callbacks.last
        lock.unlock()
        Task { @MainActor in
            callback?()
        }
    }

    private func incrementCancelCount() {
        lock.lock()
        rawCancelCount += 1
        lock.unlock()
    }
}
