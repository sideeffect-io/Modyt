import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct LightReducerTests {
    struct TransitionCase: Sendable {
        let initial: LightStore.State
        let event: LightStore.Event
        let expected: LightStore.State
        let expectedEffects: [LightStore.Effect]
    }

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        var stateMachine = LightStore.StateMachine(state: transition.initial)
        let effects = stateMachine.reduce(transition.event)
        let nextState = stateMachine.state

        #expect(nextState == transition.expected)
        #expect(effects == transition.expectedEffects)
    }

    @Test
    func changingStateEqualityIgnoresTimeoutTaskIdentity() {
        let firstTask = Task<Void, Never> {}
        let secondTask = Task<Void, Never> {}
        defer {
            firstTask.cancel()
            secondTask.cancel()
        }

        let lhs = LightStore.State.lightIsChangingInApp(
            uniqueId: Self.uniqueId,
            descriptor: Self.onDescriptor,
            expectedDescriptor: Self.onDescriptor,
            suppressedIncomingDescriptor: nil,
            timeoutTask: firstTask
        )
        let rhs = LightStore.State.lightIsChangingInApp(
            uniqueId: Self.uniqueId,
            descriptor: Self.onDescriptor,
            expectedDescriptor: Self.onDescriptor,
            suppressedIncomingDescriptor: nil,
            timeoutTask: secondTask
        )

        #expect(lhs == rhs)
    }

    private static let uniqueId = "10:1"
    private static let offDescriptor = makeDescriptor(isOn: false, level: 0)
    private static let onDescriptor = makeDescriptor(isOn: true, level: 80)
    private static let suppressedDescriptor = makeDescriptor(isOn: true, level: 30)

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle(uniqueId: uniqueId, descriptor: offDescriptor),
            event: .descriptorWasReceived(onDescriptor),
            expected: .featureIsStarted(uniqueId: uniqueId, descriptor: onDescriptor),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(uniqueId: uniqueId, descriptor: onDescriptor),
            event: .descriptorWasReceived(onDescriptor),
            expected: .featureIsStarted(uniqueId: uniqueId, descriptor: onDescriptor),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(uniqueId: uniqueId, descriptor: offDescriptor),
            event: .powerWasSetInApp(true),
            expected: .lightIsChangingInApp(
                uniqueId: uniqueId,
                descriptor: makeDescriptor(isOn: true, level: 0),
                expectedDescriptor: makeDescriptor(isOn: true, level: 0),
                suppressedIncomingDescriptor: nil
            ),
            expectedEffects: [
                .sendControlChanges(
                    uniqueId: uniqueId,
                    changes: [.init(key: "on", value: .bool(true))]
                ),
                .startTimeout,
            ]
        ),
        .init(
            initial: .featureIsStarted(uniqueId: uniqueId, descriptor: makeDescriptor(isOn: false, level: 10)),
            event: .levelNormalizedWasSetInApp(0.75),
            expected: .lightIsChangingInApp(
                uniqueId: uniqueId,
                descriptor: makeDescriptor(isOn: true, level: 75),
                expectedDescriptor: makeDescriptor(isOn: true, level: 75),
                suppressedIncomingDescriptor: nil
            ),
            expectedEffects: [
                .sendControlChanges(
                    uniqueId: uniqueId,
                    changes: [
                        .init(key: "level", value: .number(75)),
                        .init(key: "on", value: .bool(true)),
                    ]
                ),
                .startTimeout,
            ]
        ),
        .init(
            initial: .lightIsChangingInApp(
                uniqueId: uniqueId,
                descriptor: makeDescriptor(isOn: true, level: 75),
                expectedDescriptor: makeDescriptor(isOn: true, level: 75),
                suppressedIncomingDescriptor: nil
            ),
            event: .levelNormalizedWasSetInApp(0.4),
            expected: .lightIsChangingInApp(
                uniqueId: uniqueId,
                descriptor: makeDescriptor(isOn: true, level: 40),
                expectedDescriptor: makeDescriptor(isOn: true, level: 40),
                suppressedIncomingDescriptor: nil
            ),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .sendControlChanges(
                    uniqueId: uniqueId,
                    changes: [.init(key: "level", value: .number(40))]
                ),
                .startTimeout,
            ]
        ),
        .init(
            initial: .lightIsChangingInApp(
                uniqueId: uniqueId,
                descriptor: onDescriptor,
                expectedDescriptor: onDescriptor,
                suppressedIncomingDescriptor: nil
            ),
            event: .descriptorWasReceived(suppressedDescriptor),
            expected: .lightIsChangingInApp(
                uniqueId: uniqueId,
                descriptor: onDescriptor,
                expectedDescriptor: onDescriptor,
                suppressedIncomingDescriptor: suppressedDescriptor
            ),
            expectedEffects: []
        ),
        .init(
            initial: .lightIsChangingInApp(
                uniqueId: uniqueId,
                descriptor: onDescriptor,
                expectedDescriptor: onDescriptor,
                suppressedIncomingDescriptor: nil
            ),
            event: .descriptorWasReceived(makeDescriptor(isOn: true, level: 79)),
            expected: .featureIsStarted(
                uniqueId: uniqueId,
                descriptor: makeDescriptor(isOn: true, level: 79)
            ),
            expectedEffects: [.cancelTimeout(task: nil)]
        ),
        .init(
            initial: .lightIsChangingInApp(
                uniqueId: uniqueId,
                descriptor: onDescriptor,
                expectedDescriptor: onDescriptor,
                suppressedIncomingDescriptor: suppressedDescriptor
            ),
            event: .timeoutHasExpired,
            expected: .featureIsStarted(uniqueId: uniqueId, descriptor: suppressedDescriptor),
            expectedEffects: [.cancelTimeout(task: nil)]
        ),
        .init(
            initial: .featureIsStarted(uniqueId: uniqueId, descriptor: onDescriptor),
            event: .timeoutHasExpired,
            expected: .featureIsStarted(uniqueId: uniqueId, descriptor: onDescriptor),
            expectedEffects: []
        ),
    ]
}

@MainActor
struct LightStoreEffectTests {
    @Test
    func startIsIdempotent() async {
        let observeCalls = Counter()
        let streamBox = DescriptorStreamBox()

        let store = LightStore(
            uniqueId: "1:1",
            dependencies: .init(
                observeLightDescriptor: { _ in
                    await observeCalls.increment()
                    return streamBox.stream
                },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in },
                sleep: { _ in }
            )
        )

        store.start()
        store.start()

        let didCallObserveOnce = await waitUntilAsync {
            await observeCalls.value() == 1
        }
        #expect(didCallObserveOnce)
    }

    @Test
    func observationIgnoresNilDescriptor() async {
        let streamBox = DescriptorStreamBox()
        let store = LightStore(
            uniqueId: "10:1",
            dependencies: .init(
                observeLightDescriptor: { _ in streamBox.stream },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in },
                sleep: { _ in }
            )
        )
        store.start()

        streamBox.yield(nil)

        let stillIdle = await waitUntil {
            if case .featureIsIdle = store.state {
                return true
            }
            return false
        }
        #expect(stillIdle)

        streamBox.yield(makeDescriptor(isOn: true, level: 30))

        let started = await waitUntil {
            if case .featureIsStarted(_, let descriptor) = store.state {
                return descriptor == makeDescriptor(isOn: true, level: 30)
            }
            return false
        }
        #expect(started)
    }

    @Test
    func setLevelSendsOptimisticChangesBeforeCommandFanout() async {
        let streamBox = DescriptorStreamBox()
        let recorder = LightOperationRecorder()

        let store = LightStore(
            uniqueId: "10:1",
            dependencies: .init(
                observeLightDescriptor: { _ in streamBox.stream },
                applyOptimisticChanges: { uniqueId, changes in
                    await recorder.recordOptimistic(uniqueId: uniqueId, changes: changes)
                },
                sendCommand: { uniqueId, key, value in
                    await recorder.recordCommand(uniqueId: uniqueId, key: key, value: value)
                },
                sleep: { _ in
                    try? await Task.sleep(for: .seconds(3))
                }
            )
        )
        store.start()

        streamBox.yield(makeDescriptor(isOn: false, level: 0))

        let didStart = await waitUntil {
            if case .featureIsStarted(_, let descriptor) = store.state {
                return descriptor == makeDescriptor(isOn: false, level: 0)
            }
            return false
        }
        #expect(didStart)

        store.setLevelNormalized(0.6)

        let didSend = await waitUntilAsync(cycles: 2_000) {
            await recorder.count() >= 2
        }
        #expect(didSend)

        let operations = await recorder.values()
        #expect(operations.first?.kind == .optimistic)
        #expect(operations.dropFirst().allSatisfy { $0.kind == .command })
    }

    @Test
    func retargetCancelsExistingTimeoutAndStartsAnotherOne() async {
        let streamBox = DescriptorStreamBox()
        let timeoutLifecycle = TimeoutLifecycleRecorder()

        let store = LightStore(
            uniqueId: "10:1",
            dependencies: .init(
                observeLightDescriptor: { _ in streamBox.stream },
                applyOptimisticChanges: { _, _ in },
                sendCommand: { _, _, _ in },
                sleep: { _ in
                    await timeoutLifecycle.didStart()
                    do {
                        try await Task.sleep(for: .seconds(5))
                    } catch {
                        await timeoutLifecycle.didCancel()
                        throw error
                    }
                }
            )
        )
        store.start()

        streamBox.yield(makeDescriptor(isOn: true, level: 10))

        let didStart = await waitUntil {
            if case .featureIsStarted(_, let descriptor) = store.state {
                return descriptor == makeDescriptor(isOn: true, level: 10)
            }
            return false
        }
        #expect(didStart)

        store.setLevelNormalized(0.8)
        let firstTimeoutStarted = await waitUntilAsync {
            await timeoutLifecycle.startCount() == 1
        }
        #expect(firstTimeoutStarted)

        store.setLevelNormalized(0.2)
        let secondTimeoutStarted = await waitUntilAsync {
            await timeoutLifecycle.startCount() == 2
        }
        #expect(secondTimeoutStarted)

        let firstTimeoutCancelled = await waitUntilAsync {
            await timeoutLifecycle.cancelCount() >= 1
        }
        #expect(firstTimeoutCancelled)

        store.send(.descriptorWasReceived(makeDescriptor(isOn: true, level: 20)))

        let didLeaveChanging = await waitUntil {
            if case .featureIsStarted(_, let descriptor) = store.state {
                return descriptor == makeDescriptor(isOn: true, level: 20)
            }
            return false
        }
        #expect(didLeaveChanging)

        let secondTimeoutCancelled = await waitUntilAsync {
            await timeoutLifecycle.cancelCount() >= 2
        }
        #expect(secondTimeoutCancelled)
    }
}

struct LightStoreDITests {
    @Test
    func detectsLightGroupIdentifiers() {
        #expect(isLightGroupIdentifier("12"))
        #expect(isLightGroupIdentifier("group_12") == false)
        #expect(isLightGroupIdentifier("10:1") == false)
    }

    @Test
    func rejectsNonNumericGroupIdentifiers() {
        #expect(isLightGroupIdentifier("group_3") == false)
        #expect(isLightGroupIdentifier("abc") == false)
    }
}

private func makeDescriptor(
    isOn: Bool,
    level: Double,
    powerKey: String? = "on",
    levelKey: String? = "level",
    range: ClosedRange<Double> = 0...100
) -> DrivingLightControlDescriptor {
    DrivingLightControlDescriptor(
        powerKey: powerKey,
        levelKey: levelKey,
        isOn: isOn,
        level: level,
        range: range
    )
}

private final class DescriptorStreamBox: @unchecked Sendable {
    let stream: AsyncStream<DrivingLightControlDescriptor?>
    private let continuation: AsyncStream<DrivingLightControlDescriptor?>.Continuation

    init() {
        var localContinuation: AsyncStream<DrivingLightControlDescriptor?>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ value: DrivingLightControlDescriptor?) {
        continuation.yield(value)
    }
}

private actor Counter {
    private var valueStorage = 0

    func increment() {
        valueStorage += 1
    }

    func value() -> Int {
        valueStorage
    }
}

private actor LightOperationRecorder {
    enum Kind: Sendable, Equatable {
        case optimistic
        case command
    }

    struct Entry: Sendable {
        let kind: Kind
        let uniqueId: String
        let key: String?
        let value: PayloadValue?
    }

    private var entries: [Entry] = []

    func recordOptimistic(uniqueId: String, changes: [String: PayloadValue]) {
        entries.append(.init(kind: .optimistic, uniqueId: uniqueId, key: nil, value: nil))
    }

    func recordCommand(uniqueId: String, key: String, value: PayloadValue) {
        entries.append(.init(kind: .command, uniqueId: uniqueId, key: key, value: value))
    }

    func values() -> [Entry] {
        entries
    }

    func count() -> Int {
        entries.count
    }
}

private actor TimeoutLifecycleRecorder {
    private var starts = 0
    private var cancellations = 0

    func didStart() {
        starts += 1
    }

    func didCancel() {
        cancellations += 1
    }

    func startCount() -> Int {
        starts
    }

    func cancelCount() -> Int {
        cancellations
    }
}

private func waitUntil(
    cycles: Int = 120,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

private func waitUntilAsync(
    cycles: Int = 120,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}
