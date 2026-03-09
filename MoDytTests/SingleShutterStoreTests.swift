import Foundation
import Testing
@testable import MoDyt

struct ShutterPositionMapperTests {
    @Test
    func gaugePositionInvertsRawPosition() {
        #expect(ShutterPositionMapper.gaugePosition(from: 100) == 5)
        #expect(ShutterPositionMapper.gaugePosition(from: 75) == 30)
        #expect(ShutterPositionMapper.gaugePosition(from: 25) == 80)
        #expect(ShutterPositionMapper.gaugePosition(from: 0) == 105)
    }

    @Test
    func gaugePositionClampsValuesToGaugeRange() {
        #expect(ShutterPositionMapper.gaugePosition(from: -2) == 105)
        #expect(ShutterPositionMapper.gaugePosition(from: 105) == 0)
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

struct SingleShutterStateDerivedValueTests {
    private static let deviceId = DeviceIdentifier(deviceId: 10, endpointId: 1)

    @Test
    func movingStateUsesLivePositionForGaugeAndSeparateDestinationMarker() {
        let state = SingleShutterState.shutterIsMovingInApp(
            deviceId: Self.deviceId,
            position: 40,
            target: 75,
            receivedValueCountAfterInAppTarget: 0
        )

        #expect(state.gaugePosition == ShutterPositionMapper.gaugePosition(from: 40))
        #expect(state.destinationGaugePosition == ShutterPositionMapper.gaugePosition(from: 75))
        #expect(state.movementDirection == .opening)
        #expect(state.isUserInitiatedMovement)
    }

    @Test
    func externalMovingStateDoesNotReportUserInitiatedMovement() {
        let state = SingleShutterState.shutterIsMovingInApp(
            deviceId: Self.deviceId,
            position: 70,
            target: 25
        )

        #expect(state.gaugePosition == ShutterPositionMapper.gaugePosition(from: 70))
        #expect(state.destinationGaugePosition == ShutterPositionMapper.gaugePosition(from: 25))
        #expect(state.movementDirection == .closing)
        #expect(!state.isUserInitiatedMovement)
    }

    @Test
    func movingStateHidesDestinationMarkerWhenWithinCompletionTolerance() {
        let state = SingleShutterState.shutterIsMovingInApp(
            deviceId: Self.deviceId,
            position: 98,
            target: 100,
            receivedValueCountAfterInAppTarget: 2
        )

        #expect(state.destinationGaugePosition == nil)
        #expect(state.movementDirection == .idle)
    }
}

struct SingleShutterReducerTests {
    struct TransitionCase: Sendable {
        let initial: SingleShutterState
        let event: SingleShutterEvent
        let expected: SingleShutterState
        let expectedEffects: [SingleShutterEffect]
    }

    @Test(arguments: transitionCases)
    func reducerAppliesConfiguredTransition(_ transition: TransitionCase) {
        var stateMachine = SingleShutterStore.StateMachine(state: transition.initial)
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

        let lhs = SingleShutterState.shutterIsMovingInApp(
            deviceId: Self.deviceId,
            position: 33,
            target: 80,
            timeoutTask: firstTask
        )

        let rhs = SingleShutterState.shutterIsMovingInApp(
            deviceId: Self.deviceId,
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

        let initial = SingleShutterState.shutterIsMovingInApp(
            deviceId: Self.deviceId,
            position: 33,
            target: 80,
            timeoutTask: nil,
            receivedValueCountAfterInAppTarget: 1
        )

        var stateMachine = SingleShutterStore.StateMachine(state: initial)
        let effects = stateMachine.reduce(.timeoutTaskWasCreated(task: timeoutTask))
        let nextState = stateMachine.state

        #expect(effects.isEmpty)
        #expect(nextState.timeoutTask != nil)
        #expect(
            nextState == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 33,
                target: 80,
                receivedValueCountAfterInAppTarget: 1
            )
        )
    }

    @Test
    func appInitiatedMoveIgnoresSecondReceivedValue() {
        var stateMachine = SingleShutterStore.StateMachine(
            state: .featureIsStarted(
                deviceId: Self.deviceId,
                position: 100,
                target: nil
            )
        )

        let startEffects = stateMachine.reduce(.targetWasSetInApp(target: 75))
        #expect(
            startEffects == [
                .sendCommand(deviceId: Self.deviceId, position: 75),
                .startTimeout,
                .persistTarget(deviceId: Self.deviceId, target: 75),
            ]
        )
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 0
            )
        )

        let firstEffects = stateMachine.reduce(.valueWasReceived(position: 100, target: 75))
        #expect(firstEffects.isEmpty)
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 1
            )
        )

        let secondEffects = stateMachine.reduce(.valueWasReceived(position: 75, target: 75))
        #expect(secondEffects.isEmpty)
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 2
            )
        )

        let thirdEffects = stateMachine.reduce(.valueWasReceived(position: 98, target: 75))
        #expect(thirdEffects.isEmpty)
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 98,
                target: 75,
                receivedValueCountAfterInAppTarget: 3
            )
        )
    }

    @Test
    func externalTargetChangeIgnoresNextEchoedTargetValue() {
        var stateMachine = SingleShutterStore.StateMachine(
            state: .featureIsStarted(
                deviceId: Self.deviceId,
                position: 10,
                target: nil
            )
        )

        let startEffects = stateMachine.reduce(.valueWasReceived(position: 20, target: 55))
        #expect(startEffects == [.startTimeout])
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 20,
                target: 55,
                receivedValueCountAfterInAppTarget: 1
            )
        )

        let secondEffects = stateMachine.reduce(.valueWasReceived(position: 55, target: 55))
        #expect(secondEffects.isEmpty)
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 20,
                target: 55,
                receivedValueCountAfterInAppTarget: 2
            )
        )

        let thirdEffects = stateMachine.reduce(.valueWasReceived(position: 50, target: 55))
        #expect(thirdEffects.isEmpty)
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 50,
                target: 55,
                receivedValueCountAfterInAppTarget: 3
            )
        )
    }

    @Test
    func retargetResetsReceivedValueCounter() {
        var stateMachine = SingleShutterStore.StateMachine(
            state: .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 40,
                target: 60,
                receivedValueCountAfterInAppTarget: 1
            )
        )

        let retargetEffects = stateMachine.reduce(.targetWasSetInApp(target: 20))
        #expect(
            retargetEffects == [
                .cancelTimeout(task: nil),
                .sendCommand(deviceId: Self.deviceId, position: 20),
                .startTimeout,
                .persistTarget(deviceId: Self.deviceId, target: 20),
            ]
        )
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 40,
                target: 20,
                receivedValueCountAfterInAppTarget: 0
            )
        )

        let firstEffects = stateMachine.reduce(.valueWasReceived(position: 40, target: 20))
        #expect(firstEffects.isEmpty)
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 40,
                target: 20,
                receivedValueCountAfterInAppTarget: 1
            )
        )

        let secondEffects = stateMachine.reduce(.valueWasReceived(position: 20, target: 20))
        #expect(secondEffects.isEmpty)
        #expect(
            stateMachine.state == .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 40,
                target: 20,
                receivedValueCountAfterInAppTarget: 2
            )
        )
    }

    @Test
    func timeoutEndsAppInitiatedMoveAfterIgnoredSecondValue() {
        var stateMachine = SingleShutterStore.StateMachine(
            state: .shutterIsMovingInApp(
                deviceId: Self.deviceId,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 2
            )
        )

        let effects = stateMachine.reduce(.timeoutHasExpired)

        #expect(
            effects == [
                .cancelTimeout(task: nil),
                .persistTarget(deviceId: Self.deviceId, target: nil),
            ]
        )
        #expect(
            stateMachine.state == .featureIsStarted(
                deviceId: Self.deviceId,
                position: 100,
                target: nil
            )
        )
    }

    private static let deviceId = DeviceIdentifier(deviceId: 10, endpointId: 1)

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle(deviceId: deviceId, position: 0, target: nil),
            event: .valueWasReceived(position: 35, target: nil),
            expected: .featureIsStarted(deviceId: deviceId, position: 35, target: nil),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(deviceId: deviceId, position: 20, target: 10),
            event: .valueWasReceived(position: 60, target: nil),
            expected: .featureIsStarted(deviceId: deviceId, position: 60, target: nil),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(deviceId: deviceId, position: 10, target: nil),
            event: .valueWasReceived(position: 20, target: 55),
            expected: .shutterIsMovingInApp(
                deviceId: deviceId,
                position: 20,
                target: 55,
                receivedValueCountAfterInAppTarget: 1
            ),
            expectedEffects: [.startTimeout]
        ),
        .init(
            initial: .featureIsStarted(deviceId: deviceId, position: 30, target: nil),
            event: .targetWasSetInApp(target: 75),
            expected: .shutterIsMovingInApp(
                deviceId: deviceId,
                position: 30,
                target: 75,
                receivedValueCountAfterInAppTarget: 0
            ),
            expectedEffects: [
                .sendCommand(deviceId: deviceId, position: 75),
                .startTimeout,
                .persistTarget(deviceId: deviceId, target: 75),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceId: deviceId, position: 40, target: 60),
            event: .targetWasSetInApp(target: 20),
            expected: .shutterIsMovingInApp(
                deviceId: deviceId,
                position: 40,
                target: 20,
                receivedValueCountAfterInAppTarget: 0
            ),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .sendCommand(deviceId: deviceId, position: 20),
                .startTimeout,
                .persistTarget(deviceId: deviceId, target: 20),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceId: deviceId, position: 40, target: 60),
            event: .valueWasReceived(position: 45, target: 20),
            expected: .shutterIsMovingInApp(deviceId: deviceId, position: 45, target: 20),
            expectedEffects: [.cancelTimeout(task: nil), .startTimeout]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceId: deviceId, position: 20, target: 40),
            event: .valueWasReceived(position: 70, target: 70),
            expected: .featureIsStarted(deviceId: deviceId, position: 70, target: nil),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceId: deviceId, target: nil),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceId: deviceId, position: 0, target: 100),
            event: .valueWasReceived(position: 100, target: 100),
            expected: .featureIsStarted(deviceId: deviceId, position: 100, target: nil),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceId: deviceId, target: nil),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceId: deviceId, position: 0, target: 100),
            event: .valueWasReceived(position: 98, target: 100),
            expected: .featureIsStarted(deviceId: deviceId, position: 98, target: nil),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceId: deviceId, target: nil),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceId: deviceId, position: 70, target: 80),
            event: .timeoutHasExpired,
            expected: .featureIsStarted(deviceId: deviceId, position: 70, target: nil),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceId: deviceId, target: nil),
            ]
        ),
        .init(
            initial: .shutterIsMovingInApp(deviceId: deviceId, position: 70, target: 80),
            event: .targetWasSetInApp(target: 80),
            expected: .shutterIsMovingInApp(deviceId: deviceId, position: 70, target: 80),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsStarted(deviceId: deviceId, position: 42, target: nil),
            event: .timeoutHasExpired,
            expected: .featureIsStarted(deviceId: deviceId, position: 42, target: nil),
            expectedEffects: []
        ),
    ]
}

@MainActor
struct SingleShutterStoreEffectTests {
    private let id10 = DeviceIdentifier(deviceId: 10, endpointId: 1)

    @Test
    func observationKeepsGatewayPositionInStore() async {
        let streamBox = DeviceStreamBox()

        let store = SingleShutterStore(
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in
                    try await Task.sleep(for: .seconds(5))
                },
                persistTarget: { _, _ in }
            ),
            deviceId: id10
        )
        store.start()

        streamBox.yield(
            makeShutter(identifier: id10, position: 25, target: nil)
        )

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 25,
                target: nil
            )
        }

        #expect(didObserve)
    }

    @Test
    func observationKeepsRawPositionEvenWithNonPercentMetadataRange() async {
        let streamBox = DeviceStreamBox()

        let store = SingleShutterStore(
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in
                    try await Task.sleep(for: .seconds(5))
                },
                persistTarget: { _, _ in }
            ),
            deviceId: id10
        )
        store.start()

        streamBox.yield(
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
            )
        )

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 0,
                target: nil
            )
        }

        #expect(didObserve)
    }

    @Test
    func observationUsesRawSingleShutterTarget() async {
        let streamBox = DeviceStreamBox()

        let store = SingleShutterStore(
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in },
                persistTarget: { _, _ in }
            ),
            deviceId: id10
        )
        store.start()

        streamBox.yield(
            makeShutter(identifier: id10, position: 100, target: 70)
        )

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 100,
                target: 70
            )
        }

        #expect(didObserve)
    }

    @Test
    func targetWasSetInAppSendsCommandStartsTimeoutAndPersistsTarget() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedSingleShutterCommands()
        let targets = RecordedSingleShutterTargets()
        let sleepDurations = RecordedSleepDurations()

        let store = SingleShutterStore(
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                sendCommand: { deviceId, position in
                    await commands.record(deviceId: deviceId, position: position)
                },
                sleep: { duration in
                    await sleepDurations.record(duration)
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                },
                persistTarget: { deviceId, target in
                    await targets.record(deviceId: deviceId, target: target)
                }
            ),
            deviceId: id10
        )
        store.start()

        streamBox.yield(
            makeShutter(identifier: id10, position: 20, target: nil)
        )

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 20,
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
                deviceId: id10,
                position: 20,
                target: 75,
                receivedValueCountAfterInAppTarget: 0
            )
        )

        let sentCommands = await commands.values()
        #expect(sentCommands == [
            .init(deviceId: id10, position: 75)
        ])

        let persistedTargets = await targets.values()
        #expect(persistedTargets == [
            .init(deviceId: id10, target: 75)
        ])

        let durations = await sleepDurations.values()
        #expect(durations == [.seconds(60)])

        #expect(store.state.timeoutTask != nil)
    }

    @Test
    func retargetWhileMovingCancelsPreviousTimeoutAndStartsAnotherOne() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedSingleShutterCommands()
        let targets = RecordedSingleShutterTargets()
        let timeoutLifecycle = TimeoutLifecycleRecorder()

        let store = SingleShutterStore(
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                sendCommand: { deviceId, position in
                    await commands.record(deviceId: deviceId, position: position)
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
                persistTarget: { deviceId, target in
                    await targets.record(deviceId: deviceId, target: target)
                }
            ),
            deviceId: id10
        )
        store.start()

        streamBox.yield(
            makeShutter(identifier: id10, position: 20, target: nil)
        )

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 20,
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
                deviceId: id10,
                position: 20,
                target: 25,
                receivedValueCountAfterInAppTarget: 0
            )
        )

        let sentCommands = await commands.values()
        #expect(sentCommands.count == 2)
        #expect(sentCommands.contains(.init(deviceId: id10, position: 75)))
        #expect(sentCommands.contains(.init(deviceId: id10, position: 25)))

        let persistedTargets = await targets.values()
        #expect(persistedTargets.count == 2)
        #expect(persistedTargets.contains(.init(deviceId: id10, target: 75)))
        #expect(persistedTargets.contains(.init(deviceId: id10, target: 25)))
    }

    @Test
    func leavingMovingStateCancelsTimeoutAndPersistsNilTarget() async {
        let streamBox = DeviceStreamBox()
        let targets = RecordedSingleShutterTargets()
        let timeoutLifecycle = TimeoutLifecycleRecorder()

        let store = SingleShutterStore(
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
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
                persistTarget: { deviceId, target in
                    await targets.record(deviceId: deviceId, target: target)
                }
            ),
            deviceId: id10
        )
        store.start()

        streamBox.yield(
            makeShutter(identifier: id10, position: 20, target: nil)
        )

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 20,
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
                deviceId: id10,
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
        #expect(persistedTargets.contains(.init(deviceId: id10, target: 75)))
        #expect(persistedTargets.contains(.init(deviceId: id10, target: nil)))
    }

    @Test
    func appInitiatedObservationDoesNotExposeIgnoredEchoedTargetPosition() async {
        let streamBox = DeviceStreamBox()

        let store = SingleShutterStore(
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in
                    try await Task.sleep(for: .seconds(5))
                },
                persistTarget: { _, _ in }
            ),
            deviceId: id10
        )
        store.start()

        streamBox.yield(
            makeShutter(identifier: id10, position: 100, target: nil)
        )

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 100,
                target: nil
            )
        }
        #expect(didStart)

        store.send(.targetWasSetInApp(target: 75))

        let didEnterMovingState = await waitUntil {
            store.state == .shutterIsMovingInApp(
                deviceId: id10,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 0
            )
        }
        #expect(didEnterMovingState)

        streamBox.yield(
            makeShutter(identifier: id10, position: 100, target: 75)
        )

        let didObserveFirstEcho = await waitUntil {
            store.state == .shutterIsMovingInApp(
                deviceId: id10,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 1
            )
        }
        #expect(didObserveFirstEcho)

        streamBox.yield(
            makeShutter(identifier: id10, position: 75, target: 75)
        )

        let didIgnoreSecondEcho = await waitUntil {
            store.state == .shutterIsMovingInApp(
                deviceId: id10,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 2
            )
        }
        #expect(didIgnoreSecondEcho)

        streamBox.yield(
            makeShutter(identifier: id10, position: 98, target: 75)
        )

        let didObserveRealMovement = await waitUntil {
            store.state == .shutterIsMovingInApp(
                deviceId: id10,
                position: 98,
                target: 75,
                receivedValueCountAfterInAppTarget: 3
            )
        }
        #expect(didObserveRealMovement)
    }

    @Test
    func externalObservationDoesNotExposeIgnoredEchoedTargetPosition() async {
        let streamBox = DeviceStreamBox()

        let store = SingleShutterStore(
            dependencies: .init(
                observeDevice: { _ in streamBox.stream },
                sendCommand: { _, _ in },
                sleep: { _ in
                    try await Task.sleep(for: .seconds(5))
                },
                persistTarget: { _, _ in }
            ),
            deviceId: id10
        )
        store.start()

        streamBox.yield(
            makeShutter(identifier: id10, position: 100, target: nil)
        )

        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 100,
                target: nil
            )
        }
        #expect(didStart)

        streamBox.yield(
            makeShutter(identifier: id10, position: 100, target: 75)
        )

        let didEnterMovingState = await waitUntil {
            store.state == .shutterIsMovingInApp(
                deviceId: id10,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 1
            )
        }
        #expect(didEnterMovingState)

        streamBox.yield(
            makeShutter(identifier: id10, position: 75, target: 75)
        )

        let didIgnoreEchoedCompletion = await waitUntil {
            store.state == .shutterIsMovingInApp(
                deviceId: id10,
                position: 100,
                target: 75,
                receivedValueCountAfterInAppTarget: 2
            )
        }
        #expect(didIgnoreEchoedCompletion)

        streamBox.yield(
            makeShutter(identifier: id10, position: 98, target: 75)
        )

        let didObserveRealMovement = await waitUntil {
            store.state == .shutterIsMovingInApp(
                deviceId: id10,
                position: 98,
                target: 75,
                receivedValueCountAfterInAppTarget: 3
            )
        }
        #expect(didObserveRealMovement)
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

private final class DeviceStreamBox: @unchecked Sendable {
    let stream: AsyncStream<Device?>
    private let continuation: AsyncStream<Device?>.Continuation

    init() {
        var localContinuation: AsyncStream<Device?>.Continuation?
        self.stream = AsyncStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ value: Device?) {
        continuation.yield(value)
    }
}

private actor RecordedSingleShutterCommands {
    struct Entry: Sendable, Equatable {
        let deviceId: DeviceIdentifier
        let position: Int
    }

    private var entries: [Entry] = []

    func record(deviceId: DeviceIdentifier, position: Int) {
        entries.append(.init(deviceId: deviceId, position: position))
    }

    func values() -> [Entry] {
        entries
    }
}

private actor RecordedSingleShutterTargets {
    struct Entry: Sendable, Equatable {
        let deviceId: DeviceIdentifier
        let target: Int?
    }

    private var entries: [Entry] = []

    func record(deviceId: DeviceIdentifier, target: Int?) {
        entries.append(.init(deviceId: deviceId, target: target))
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
