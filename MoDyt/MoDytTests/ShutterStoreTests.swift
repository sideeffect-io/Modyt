import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct ShutterStoreTests {
    @Test
    func reducer_idleReceivedEqualTransitionsToIdleWithoutEffects() {
        let state = ShuttersState.idle(Positions(actual: .open, target: .quarter))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: .half, target: .half)
        )

        #expect(next == .idle(Positions(actual: .half, target: .half)))
        #expect(effects.isEmpty)
    }

    @Test
    func reducer_idleReceivedDifferentTransitionsToMovingAndStartsTimer() {
        let state = ShuttersState.idle(Positions(actual: .open, target: .open))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: .quarter, target: .half)
        )

        #expect(next == .moving(Positions(actual: .quarter, target: .half)))
        #expect(effects == [.startCompletionTimer])
    }

    @Test
    func reducer_idleSetTargetTransitionsToMovingWithOrderedEffects() {
        let state = ShuttersState.idle(Positions(actual: .open, target: .open))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .setTarget(value: .half)
        )

        #expect(next == .moving(Positions(actual: .open, target: .half)))
        #expect(effects == [.handleTarget(value: .half), .startCompletionTimer])
    }

    @Test
    func reducer_movingReceivedEqualTransitionsToIdleAndCancelsTimer() {
        let state = ShuttersState.moving(Positions(actual: .quarter, target: .half))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: .half, target: .half)
        )

        #expect(next == .idle(Positions(actual: .half, target: .half)))
        #expect(effects == [.cancelCompletionTimer])
    }

    @Test
    func reducer_movingFailedToCompleteTransitionsToIdleWithoutEffects() {
        let state = ShuttersState.moving(Positions(actual: .quarter, target: .half))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .failedToComplete
        )

        #expect(next == .idle(Positions(actual: .quarter, target: .half)))
        #expect(effects.isEmpty)
    }

    @Test
    func reducer_movingReceivedDifferentWithSameTargetUpdatesActualWithoutEffects() {
        let state = ShuttersState.moving(Positions(actual: .open, target: .half))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: .quarter, target: .half)
        )

        #expect(next == .moving(Positions(actual: .quarter, target: .half)))
        #expect(effects.isEmpty)
    }

    @Test
    func reducer_movingReceivedDifferentWithNewTargetRestartsTimer() {
        let state = ShuttersState.moving(Positions(actual: .open, target: .half))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .receivedValuesFromStream(actual: .quarter, target: .threeQuarter)
        )

        #expect(next == .moving(Positions(actual: .quarter, target: .threeQuarter)))
        #expect(effects == [.cancelCompletionTimer, .startCompletionTimer])
    }

    @Test
    func reducer_movingSetTargetTransitionsWithOrderedEffects() {
        let state = ShuttersState.moving(Positions(actual: .quarter, target: .half))

        let (next, effects) = ShuttersReducer.reduce(
            state: state,
            event: .setTarget(value: .closed)
        )

        #expect(next == .moving(Positions(actual: .quarter, target: .closed)))
        #expect(effects == [.handleTarget(value: .closed), .cancelCompletionTimer, .startCompletionTimer])
    }

    @Test
    func observePositionsStreamDrivesReceivedValuesEvent() async {
        let streamBox = BufferedStreamBox<(actual: ShutterStep, target: ShutterStep)>()
        let store = ShutterStore(
            shutterUniqueIds: ["shutter-1"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                startCompletionTimer: { _ in Task { } }
            )
        )

        streamBox.yield((actual: .quarter, target: .half))
        let didMove = await waitUntil {
            store.state == .moving(Positions(actual: .quarter, target: .half))
        }

        #expect(didMove)
        #expect(store.actualStep == .quarter)
        #expect(store.targetStep == .half)
        #expect(store.isMoving)
    }

    @Test
    func setTargetCallsSendTargetPositionWithExactIdsAndStep() async throws {
        let recorder = TestRecorder<([String], ShutterStep)>()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1", "id-2"],
            dependencies: .init(
                observePositions: { _ in
                    AsyncStream { continuation in
                        continuation.finish()
                    }
                },
                sendTargetPosition: { ids, step in
                    await recorder.record((ids, step))
                },
                startCompletionTimer: { _ in Task { } }
            )
        )

        store.send(.setTarget(value: .threeQuarter))

        let didRecord = await waitUntil {
            await recorder.values.count == 1
        }

        #expect(didRecord)
        let entries = await recorder.values
        #expect(entries.count == 1)
        let first = try #require(entries.first)
        #expect(first.0 == ["id-1", "id-2"])
        #expect(first.1 == .threeQuarter)
    }

    @Test
    func movingToIdleFromStreamCancelsCompletionTimer() async {
        let streamBox = BufferedStreamBox<(actual: ShutterStep, target: ShutterStep)>()
        let timer = CompletionTimerHarness()

        let store = ShutterStore(
            shutterUniqueIds: ["id-1"],
            dependencies: .init(
                observePositions: { _ in streamBox.stream },
                sendTargetPosition: { _, _ in },
                startCompletionTimer: timer.start
            )
        )

        store.send(.setTarget(value: .closed))
        let didStartMoving = await waitUntil {
            store.state == .moving(Positions(actual: .open, target: .closed))
                && timer.startCount == 1
        }
        #expect(didStartMoving)
        #expect(store.state == .moving(Positions(actual: .open, target: .closed)))
        #expect(timer.startCount == 1)

        streamBox.yield((actual: .closed, target: .closed))
        let becameIdle = await waitUntil {
            store.state == .idle(Positions(actual: .closed, target: .closed))
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

        store.send(.setTarget(value: .half))
        let didStartMoving = await waitUntil {
            store.state == .moving(Positions(actual: .open, target: .half))
        }
        #expect(didStartMoving)
        #expect(store.state == .moving(Positions(actual: .open, target: .half)))

        timer.triggerLatest()

        let becameIdleAfterFailure = await waitUntil {
            store.state == .idle(Positions(actual: .open, target: .half))
        }

        #expect(becameIdleAfterFailure)
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
            target: .quarter,
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
            target: .quarter,
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
