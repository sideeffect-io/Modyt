import Foundation
import Testing
@testable import MoDyt

struct ShutterPositionMapperTests {
    @Test
    func gaugePositionInvertsRawPosition() {
        #expect(ShutterPositionMapper.gaugePosition(from: 100) == 0)
        #expect(ShutterPositionMapper.gaugePosition(from: 75) == 25)
        #expect(ShutterPositionMapper.gaugePosition(from: 25) == 75)
        #expect(ShutterPositionMapper.gaugePosition(from: 0) == 100)
    }

    @Test
    func gaugePositionClampsValuesToPercentRange() {
        #expect(ShutterPositionMapper.gaugePosition(from: -2) == 100)
        #expect(ShutterPositionMapper.gaugePosition(from: 123) == 0)
    }
}

struct DeviceShutterPositionTests {
    @Test
    func shutterDescriptorPrefersPositionSignalOverLevel() {
        let device = Device(
            id: .init(deviceId: 10, endpointId: 1),
            deviceId: 10,
            endpointId: 1,
            name: "Shutter",
            usage: "shutter",
            kind: "shutter",
            data: [
                "position": .number(30),
                "level": .number(90),
            ],
            metadata: nil,
            isFavorite: false,
            dashboardOrder: nil,
            shutterTargetPosition: nil,
            updatedAt: Date()
        )

        #expect(device.shutterControlDescriptor()?.key == "position")
        #expect(device.shutterPosition == 30)
    }
}

struct ShutterReducerTests {
    struct TransitionCase: Sendable {
        let initial: ShutterState
        let event: ShutterEvent
        let expected: ShutterState
        let expectedEffects: [ShutterEffect]
    }

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        var stateMachine = ShutterStore.StateMachine(state: transition.initial)
        let effects = stateMachine.reduce(transition.event)
        let nextState = stateMachine.state

        #expect(nextState == transition.expected)
        #expect(effects == transition.expectedEffects)
    }

    @Test
    func movingStateEqualityIgnoresTimeoutTaskIdentity() {
        let firstTask = Task<Void, Never> {}
        let secondTask = Task<Void, Never> {}
        defer {
            firstTask.cancel()
            secondTask.cancel()
        }

        let lhs = ShutterState.shutterIsMovingInApp(
            deviceIds: Self.deviceIds,
            position: 33,
            target: 80,
            timeoutTask: firstTask
        )

        let rhs = ShutterState.shutterIsMovingInApp(
            deviceIds: Self.deviceIds,
            position: 33,
            target: 80,
            timeoutTask: secondTask
        )

        #expect(lhs == rhs)
    }

    @Test
    func timeoutTaskWasCreatedAssignsTaskInMovingState() {
        let timeoutTask = Task<Void, Never> {}
        defer { timeoutTask.cancel() }

        let initial = ShutterState.shutterIsMovingInApp(
            deviceIds: Self.deviceIds,
            position: 33,
            target: 80,
            timeoutTask: nil
        )

        var stateMachine = ShutterStore.StateMachine(state: initial)
        let effects = stateMachine.reduce(.timeoutTaskWasCreated(task: timeoutTask))
        let nextState = stateMachine.state

        #expect(effects.isEmpty)
        #expect(nextState.timeoutTask != nil)
        #expect(nextState == .shutterIsMovingInApp(deviceIds: Self.deviceIds, position: 33, target: 80))
    }

    private static let deviceIds: [DeviceIdentifier] = [
        .init(deviceId: 10, endpointId: 1),
        .init(deviceId: 11, endpointId: 1),
    ]

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle(deviceIds: deviceIds, position: 0, target: nil),
            event: .valueWasReceived(position: 35, target: nil),
            expected: .featureIsStarted(deviceIds: deviceIds, position: 35, target: nil),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(deviceIds: deviceIds, position: 20, target: 10),
            event: .valueWasReceived(position: 60, target: nil),
            expected: .featureIsStarted(deviceIds: deviceIds, position: 60, target: nil),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(deviceIds: deviceIds, position: 10, target: nil),
            event: .valueWasReceived(position: 20, target: 55),
            expected: .shutterIsMovingInApp(deviceIds: deviceIds, position: 20, target: 55),
            expectedEffects: [.startTimeout]
        ),
        .init(
            initial: .featureIsStarted(deviceIds: deviceIds, position: 30, target: nil),
            event: .targetWasSetInApp(target: 75),
            expected: .shutterIsMovingInApp(deviceIds: deviceIds, position: 30, target: 75),
            expectedEffects: [
                .sendCommand(deviceIds: deviceIds, position: 75),
                .startTimeout,
                .persistTarget(deviceIds: deviceIds, target: 75),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 40, target: 60),
            event: .targetWasSetInApp(target: 20),
            expected: .shutterIsMovingInApp(deviceIds: deviceIds, position: 40, target: 20),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .sendCommand(deviceIds: deviceIds, position: 20),
                .startTimeout,
                .persistTarget(deviceIds: deviceIds, target: 20),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 40, target: 60),
            event: .valueWasReceived(position: 45, target: 20),
            expected: .shutterIsMovingInApp(deviceIds: deviceIds, position: 45, target: 20),
            expectedEffects: [.cancelTimeout(task: nil), .startTimeout]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 20, target: 40),
            event: .valueWasReceived(position: 70, target: 70),
            expected: .featureIsStarted(deviceIds: deviceIds, position: 70, target: nil),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceIds: deviceIds, target: nil),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 0, target: 100),
            event: .valueWasReceived(position: 100, target: 100),
            expected: .featureIsStarted(deviceIds: deviceIds, position: 100, target: nil),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceIds: deviceIds, target: nil),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 0, target: 100),
            event: .valueWasReceived(position: 98, target: 100),
            expected: .featureIsStarted(deviceIds: deviceIds, position: 98, target: nil),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceIds: deviceIds, target: nil),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 70, target: 80),
            event: .timeoutHasExpired,
            expected: .featureIsStarted(deviceIds: deviceIds, position: 70, target: nil),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceIds: deviceIds, target: nil),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceIds: deviceIds, position: 70, target: 80),
            event: .targetWasSetInApp(target: 80),
            expected: .shutterIsMovingInApp(deviceIds: deviceIds, position: 70, target: 80),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(deviceIds: deviceIds, position: 42, target: nil),
            event: .timeoutHasExpired,
            expected: .featureIsStarted(deviceIds: deviceIds, position: 42, target: nil),
            expectedEffects: []
        ),
    ]
}

@MainActor
struct ShutterStoreEffectTests {
    private let id10 = DeviceIdentifier(deviceId: 10, endpointId: 1)
    private let id11 = DeviceIdentifier(deviceId: 11, endpointId: 1)

    @Test
    func observationKeepsGatewayPositionInStore() async {
        let streamBox = DeviceArrayStreamBox()

        let store = ShutterStore(
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in },
                persistTarget: { _, _ in }
            ),
            deviceIds: [id10]
        )
        store.start()

        streamBox.yield([
            makeShutter(identifier: id10, position: 25, target: nil),
        ])

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10],
                position: 25,
                target: nil
            )
        }

        #expect(didObserve)
    }

    @Test
    func observationKeepsRawPositionEvenWithNonPercentMetadataRange() async {
        let streamBox = DeviceArrayStreamBox()

        let store = ShutterStore(
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in },
                persistTarget: { _, _ in }
            ),
            deviceIds: [id10]
        )
        store.start()

        streamBox.yield([
            Device(
                id: id10,
                deviceId: id10.deviceId,
                endpointId: 1,
                name: "Shutter \(id10.deviceId):\(id10.endpointId)",
                usage: "shutter",
                kind: "shutter",
                data: ["position": .number(0.2)],
                metadata: ["position": .object(["min": .number(0), "max": .number(1)])],
                isFavorite: false,
                dashboardOrder: nil,
                shutterTargetPosition: nil,
                updatedAt: Date()
            ),
        ])

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10],
                position: 0,
                target: nil
            )
        }

        #expect(didObserve)
    }

    @Test
    func observationAveragesMultiShutterValuesWhenAllTargetsArePresent() async {
        let streamBox = DeviceArrayStreamBox()
        let commands = RecordedShutterCommands()
        let targets = RecordedShutterTargets()

        let store = ShutterStore(
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                },
                sleep: { _ in
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                },
                persistTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            ),
            deviceIds: [id10, id11]
        )
        store.start()

        streamBox.yield([
            makeShutter(identifier: id10, position: 100, target: 70),
            makeShutter(identifier: id11, position: 0, target: 40),
        ])

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10, id11],
                position: 50,
                target: 55
            )
        }

        #expect(didObserve)
        #expect(await commands.values().isEmpty)
        #expect(await targets.values().isEmpty)
    }

    @Test
    func observationAveragesAvailableTargetsWhenOneShutterHasNoTarget() async {
        let streamBox = DeviceArrayStreamBox()

        let store = ShutterStore(
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in },
                persistTarget: { _, _ in }
            ),
            deviceIds: [id10, id11]
        )
        store.start()

        streamBox.yield([
            makeShutter(identifier: id10, position: 100, target: nil),
            makeShutter(identifier: id11, position: 0, target: 40),
        ])

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10, id11],
                position: 50,
                target: 40
            )
        }

        #expect(didObserve)
    }

    @Test
    func targetWasSetInAppSendsCommandStartsTimeoutAndPersistsTarget() async {
        let streamBox = DeviceArrayStreamBox()
        let commands = RecordedShutterCommands()
        let targets = RecordedShutterTargets()
        let sleepDurations = RecordedSleepDurations()

        let store = ShutterStore(
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                },
                sleep: { duration in
                    await sleepDurations.record(duration)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                },
                persistTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            ),
            deviceIds: [id10, id11]
        )
        store.start()

        streamBox.yield([
            makeShutter(identifier: id10, position: 20, target: nil),
            makeShutter(identifier: id11, position: 40, target: nil),
        ])

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10, id11],
                position: 30,
                target: nil
            )
        }
        #expect(didStart)

        store.send(.targetWasSetInApp(target: 75))

        let didEmitEffects = await waitUntilAsync {
            let sentCommands = await commands.values()
            let persistedTargets = await targets.values()
            let durations = await sleepDurations.values()
            return sentCommands.count == 1 && persistedTargets.count == 1 && durations.count == 1
        }
        #expect(didEmitEffects)

        #expect(
            store.state == .shutterIsMovingInApp(
                deviceIds: [id10, id11],
                position: 30,
                target: 75
            )
        )

        let sentCommands = await commands.values()
        #expect(sentCommands == [
            .init(deviceIds: [id10, id11], position: 75)
        ])

        let persistedTargets = await targets.values()
        #expect(persistedTargets == [
            .init(deviceIds: [id10, id11], target: 75)
        ])

        let durations = await sleepDurations.values()
        #expect(durations == [.seconds(60)])

        #expect(store.state.timeoutTask != nil)
    }

    @Test
    func retargetWhileMovingCancelsPreviousTimeoutAndStartsAnotherOne() async {
        let streamBox = DeviceArrayStreamBox()
        let commands = RecordedShutterCommands()
        let targets = RecordedShutterTargets()
        let timeoutLifecycle = TimeoutLifecycleRecorder()

        let store = ShutterStore(
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { deviceIds, position in
                    await commands.record(deviceIds: deviceIds, position: position)
                },
                sleep: { _ in
                    await timeoutLifecycle.didStart()
                    do {
                        try await Task.sleep(for: .seconds(5))
                    } catch {
                        await timeoutLifecycle.didCancel()
                        throw error
                    }
                },
                persistTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            ),
            deviceIds: [id10, id11]
        )
        store.start()

        streamBox.yield([
            makeShutter(identifier: id10, position: 20, target: nil),
            makeShutter(identifier: id11, position: 40, target: nil),
        ])

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10, id11],
                position: 30,
                target: nil
            )
        }
        #expect(didStart)

        store.send(.targetWasSetInApp(target: 75))

        let firstTimeoutStarted = await waitUntilAsync {
            await timeoutLifecycle.startCount() == 1
        }
        #expect(firstTimeoutStarted)

        store.send(.targetWasSetInApp(target: 25))

        let secondTimeoutStarted = await waitUntilAsync {
            await timeoutLifecycle.startCount() == 2
        }
        #expect(secondTimeoutStarted)

        let firstTimeoutCancelled = await waitUntilAsync {
            await timeoutLifecycle.cancelCount() >= 1
        }
        #expect(firstTimeoutCancelled)

        #expect(
            store.state == .shutterIsMovingInApp(
                deviceIds: [id10, id11],
                position: 30,
                target: 25
            )
        )

        let sentCommands = await commands.values()
        #expect(sentCommands.count == 2)
        #expect(sentCommands.contains(.init(deviceIds: [id10, id11], position: 75)))
        #expect(sentCommands.contains(.init(deviceIds: [id10, id11], position: 25)))

        let persistedTargets = await targets.values()
        #expect(persistedTargets.count == 2)
        #expect(persistedTargets.contains(.init(deviceIds: [id10, id11], target: 75)))
        #expect(persistedTargets.contains(.init(deviceIds: [id10, id11], target: 25)))
    }

    @Test
    func leavingMovingStateCancelsTimeoutAndPersistsNilTarget() async {
        let streamBox = DeviceArrayStreamBox()
        let targets = RecordedShutterTargets()
        let timeoutLifecycle = TimeoutLifecycleRecorder()

        let store = ShutterStore(
            dependencies: .init(
                observeDevices: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in
                    await timeoutLifecycle.didStart()
                    do {
                        try await Task.sleep(for: .seconds(5))
                    } catch {
                        await timeoutLifecycle.didCancel()
                        throw error
                    }
                },
                persistTarget: { deviceIds, target in
                    await targets.record(deviceIds: deviceIds, target: target)
                }
            ),
            deviceIds: [id10, id11]
        )
        store.start()

        streamBox.yield([
            makeShutter(identifier: id10, position: 20, target: nil),
            makeShutter(identifier: id11, position: 40, target: nil),
        ])

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10, id11],
                position: 30,
                target: nil
            )
        }
        #expect(didStart)

        store.send(.targetWasSetInApp(target: 75))

        let timeoutStarted = await waitUntilAsync {
            await timeoutLifecycle.startCount() == 1
        }
        #expect(timeoutStarted)

        store.send(.valueWasReceived(position: 75, target: 75))

        let didStopMoving = await waitUntil {
            store.state == .featureIsStarted(
                deviceIds: [id10, id11],
                position: 75,
                target: nil
            )
        }
        #expect(didStopMoving)

        let timeoutCancelled = await waitUntilAsync {
            await timeoutLifecycle.cancelCount() >= 1
        }
        #expect(timeoutCancelled)

        #expect(store.state.timeoutTask == nil)

        let didPersistTwoTargets = await waitUntilAsync {
            await targets.values().count == 2
        }
        #expect(didPersistTwoTargets)

        let persistedTargets = await targets.values()
        #expect(persistedTargets.contains(.init(deviceIds: [id10, id11], target: 75)))
        #expect(persistedTargets.contains(.init(deviceIds: [id10, id11], target: nil)))
    }

    private func makeShutter(
        identifier: DeviceIdentifier,
        position: Int,
        target: Int?
    ) -> Device {
        Device(
            id: identifier,
            deviceId: identifier.deviceId,
            endpointId: identifier.endpointId,
            name: "Shutter \(identifier.deviceId):\(identifier.endpointId)",
            usage: "shutter",
            kind: "shutter",
            data: ["position": .number(Double(position))],
            metadata: nil,
            isFavorite: false,
            dashboardOrder: nil,
            shutterTargetPosition: target,
            updatedAt: Date()
        )
    }

    private func waitUntil(
        cycles: Int = 120,
        condition: @escaping @MainActor () -> Bool
    ) async -> Bool {
        for _ in 0..<cycles {
            if condition() {
                return true
            }
            await Task.yield()
        }
        return condition()
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
}

private final class DeviceArrayStreamBox: @unchecked Sendable {
    let stream: AsyncStream<[Device]>
    private let continuation: AsyncStream<[Device]>.Continuation

    init() {
        var localContinuation: AsyncStream<[Device]>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ values: [Device]) {
        continuation.yield(values)
    }
}

private actor RecordedShutterCommands {
    struct Entry: Sendable, Equatable {
        let deviceIds: [DeviceIdentifier]
        let position: Int
    }

    private var entries: [Entry] = []

    func record(deviceIds: [DeviceIdentifier], position: Int) {
        entries.append(.init(deviceIds: deviceIds, position: position))
    }

    func values() -> [Entry] {
        entries
    }
}

private actor RecordedShutterTargets {
    struct Entry: Sendable, Equatable {
        let deviceIds: [DeviceIdentifier]
        let target: Int?
    }

    private var entries: [Entry] = []

    func record(deviceIds: [DeviceIdentifier], target: Int?) {
        entries.append(.init(deviceIds: deviceIds, target: target))
    }

    func values() -> [Entry] {
        entries
    }
}

private actor RecordedSleepDurations {
    private var durations: [Duration] = []

    func record(_ duration: Duration) {
        durations.append(duration)
    }

    func values() -> [Duration] {
        durations
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
