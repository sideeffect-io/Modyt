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
    func localTargetMovementUsesLivePositionForGaugeAndSeparateDestinationMarker() {
        let state = SingleShutterState.shutterIsMovingToLocalTarget(
            deviceId: Self.deviceId,
            position: 40,
            target: 75,
            ignoresNextMatchingPosition: true
        )

        #expect(state.gaugePosition == ShutterPositionMapper.gaugePosition(from: 40))
        #expect(state.destinationGaugePosition == ShutterPositionMapper.gaugePosition(from: 75))
        #expect(state.movementDirection == .opening)
        #expect(state.isUserInitiatedMovement)
    }

    @Test
    func pendingLocalTargetOutsideMovementDoesNotExposeDestinationMarker() {
        let state = SingleShutterState.featureIsStarted(
            deviceId: Self.deviceId,
            position: 70,
            pendingLocalTarget: 25
        )

        #expect(state.gaugePosition == ShutterPositionMapper.gaugePosition(from: 70))
        #expect(state.destinationGaugePosition == nil)
        #expect(state.movementDirection == .idle)
        #expect(state.movingTarget == nil)
        #expect(!state.isMovingInApp)
    }

    @Test
    func movingStateHidesDestinationMarkerWhenWithinCompletionTolerance() {
        let state = SingleShutterState.shutterIsMovingToLocalTarget(
            deviceId: Self.deviceId,
            position: 98,
            target: 100
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
        let transitionResult = SingleShutterStore.StateMachine.reduce(
            transition.initial,
            transition.event
        )

        #expect(transitionResult.state == transition.expected)
        #expect(transitionResult.effects == transition.expectedEffects)
    }

    @Test
    func movingStateEqualityIgnoresTimeoutTaskIdentity() {
        let firstTask = Task<Void, Never> {}
        let secondTask = Task<Void, Never> {}
        defer {
            firstTask.cancel()
            secondTask.cancel()
        }

        let lhs = SingleShutterState.shutterIsMovingToLocalTarget(
            deviceId: Self.deviceId,
            position: 33,
            target: 80,
            timeoutTask: firstTask,
            ignoresNextMatchingPosition: true
        )

        let rhs = SingleShutterState.shutterIsMovingToLocalTarget(
            deviceId: Self.deviceId,
            position: 33,
            target: 80,
            timeoutTask: secondTask,
            ignoresNextMatchingPosition: true
        )

        #expect(lhs == rhs)
    }

    @Test
    func timeoutTaskWasCreatedAssignsTaskInMovingState() {
        let timeoutTask = Task<Void, Never> {}
        defer { timeoutTask.cancel() }

        let initial = SingleShutterState.shutterIsMovingToLocalTarget(
            deviceId: Self.deviceId,
            position: 33,
            target: 80,
            ignoresNextMatchingPosition: true
        )

        let transition = SingleShutterStore.StateMachine.reduce(
            initial,
            .timeoutTaskWasCreated(task: timeoutTask)
        )

        #expect(transition.effects.isEmpty)
        #expect(transition.state.timeoutTask != nil)
        #expect(
            transition.state == .shutterIsMovingToLocalTarget(
                deviceId: Self.deviceId,
                position: 33,
                target: 80,
                ignoresNextMatchingPosition: true
            )
        )
    }

    @Test
    func movingToLocalTargetIgnoresFirstMatchingPositionOnly() {
        let initial = SingleShutterState.shutterIsMovingToLocalTarget(
            deviceId: Self.deviceId,
            position: 100,
            target: 75,
            ignoresNextMatchingPosition: true
        )

        let ignoredTransition = SingleShutterStore.StateMachine.reduce(
            initial,
            .positionWasReceived(position: 75)
        )
        #expect(ignoredTransition.effects.isEmpty)
        #expect(
            ignoredTransition.state == .shutterIsMovingToLocalTarget(
                deviceId: Self.deviceId,
                position: 100,
                target: 75,
                ignoresNextMatchingPosition: false
            )
        )

        let completionTransition = SingleShutterStore.StateMachine.reduce(
            ignoredTransition.state,
            .positionWasReceived(position: 75)
        )
        #expect(
            completionTransition.effects == [
                .cancelTimeout(task: nil),
                .persistTarget(deviceId: Self.deviceId, target: nil),
            ]
        )
        #expect(
            completionTransition.state == .featureIsStarted(
                deviceId: Self.deviceId,
                position: 75,
                pendingLocalTarget: nil
            )
        )
    }

    @Test
    func settingCurrentTargetOnlySendsCommandWithoutEnteringMovingState() {
        let transition = SingleShutterStore.StateMachine.reduce(
            .featureIsStarted(
                deviceId: Self.deviceId,
                position: 75,
                pendingLocalTarget: nil
            ),
            .targetWasSetInApp(target: 75)
        )

        #expect(
            transition.effects == [
                .sendCommand(deviceId: Self.deviceId, position: 75)
            ]
        )
        #expect(
            transition.state == .featureIsStarted(
                deviceId: Self.deviceId,
                position: 75,
                pendingLocalTarget: nil
            )
        )
    }

    private static let deviceId = DeviceIdentifier(deviceId: 10, endpointId: 1)

    private static let transitionCases: [TransitionCase] = [
        .init(
            initial: .featureIsIdle(deviceId: deviceId, position: 0, pendingLocalTarget: nil),
            event: .positionWasReceived(position: 35),
            expected: .featureIsStarted(deviceId: deviceId, position: 35, pendingLocalTarget: nil),
            expectedEffects: []
        ),
        .init(
            initial: .featureIsIdle(deviceId: deviceId, position: 0, pendingLocalTarget: 55),
            event: .positionWasReceived(position: 55),
            expected: .featureIsStarted(deviceId: deviceId, position: 55, pendingLocalTarget: nil),
            expectedEffects: [
                .persistTarget(deviceId: deviceId, target: nil)
            ]
        ),
        .init(
            initial: .featureIsStarted(deviceId: deviceId, position: 20, pendingLocalTarget: nil),
            event: .pendingLocalTargetWasObserved(target: 55),
            expected: .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: 20,
                target: 55,
                ignoresNextMatchingPosition: true
            ),
            expectedEffects: [.startTimeout]
        ),
        .init(
            initial: .featureIsStarted(deviceId: deviceId, position: 30, pendingLocalTarget: nil),
            event: .targetWasSetInApp(target: 75),
            expected: .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: 30,
                target: 75,
                ignoresNextMatchingPosition: true
            ),
            expectedEffects: [
                .sendCommand(deviceId: deviceId, position: 75),
                .startTimeout,
                .persistTarget(deviceId: deviceId, target: 75),
            ]
        ),
        .init(
            initial: .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: 40,
                target: 60,
                ignoresNextMatchingPosition: false
            ),
            event: .pendingLocalTargetWasObserved(target: 20),
            expected: .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: 40,
                target: 20,
                ignoresNextMatchingPosition: true
            ),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .startTimeout,
            ]
        ),
        .init(
            initial: .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: 40,
                target: 60,
                ignoresNextMatchingPosition: false
            ),
            event: .pendingLocalTargetWasObserved(target: nil),
            expected: .featureIsStarted(
                deviceId: deviceId,
                position: 40,
                pendingLocalTarget: nil
            ),
            expectedEffects: [
                .cancelTimeout(task: nil)
            ]
        ),
        .init(
            initial: .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: 45,
                target: 20,
                ignoresNextMatchingPosition: false
            ),
            event: .positionWasReceived(position: 25),
            expected: .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: 25,
                target: 20,
                ignoresNextMatchingPosition: false
            ),
            expectedEffects: []
        ),
        .init(
            initial: .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: 70,
                target: 80,
                ignoresNextMatchingPosition: false
            ),
            event: .timeoutHasExpired,
            expected: .featureIsStarted(
                deviceId: deviceId,
                position: 70,
                pendingLocalTarget: nil
            ),
            expectedEffects: [
                .cancelTimeout(task: nil),
                .persistTarget(deviceId: deviceId, target: nil),
            ]
        ),
    ]
}

@MainActor
struct SingleShutterStoreEffectTests {
    private let id10 = DeviceIdentifier(deviceId: 10, endpointId: 1)

    @Test
    func observationKeepsGatewayPositionInStore() async {
        let streamBox = DeviceStreamBox()

        let store = makeStore(streamBox: streamBox)
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 25, target: nil))

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 25,
                pendingLocalTarget: nil
            )
        }

        #expect(didObserve)
    }

    @Test
    func observationKeepsRawPositionEvenWithNonPercentMetadataRange() async {
        let streamBox = DeviceStreamBox()

        let store = makeStore(streamBox: streamBox)
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
                pendingLocalTarget: nil
            )
        }

        #expect(didObserve)
    }

    @Test
    func initialPendingLocalTargetStartsLocalTargetMovement() async {
        let streamBox = DeviceStreamBox()
        let sleepDurations = RecordedSleepDurations()
        let testTime = ManualTestClock()

        let store = makeStore(
            streamBox: streamBox,
            sleep: { duration in
                await sleepDurations.record(duration)
                try await testTime.sleep(for: duration)
            }
        )
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 100, target: 70))

        let didObserve = await waitUntil {
            store.state == .shutterIsMovingToLocalTarget(
                deviceId: id10,
                position: 100,
                target: 70,
                ignoresNextMatchingPosition: true
            )
        }

        #expect(didObserve)
        #expect(store.gaugePosition == ShutterPositionMapper.gaugePosition(from: 100))
        #expect(store.movingTarget == 70)

        let didRecordTimeoutDuration = await waitUntilAsync {
            await sleepDurations.values() == [.seconds(60)]
        }
        #expect(didRecordTimeoutDuration)

        let didCaptureTimeoutTask = await waitUntil {
            store.state.timeoutTask != nil
        }
        #expect(didCaptureTimeoutTask)
    }

    @Test
    func initialPendingLocalTargetAlreadyAtDestinationIsCleared() async {
        let streamBox = DeviceStreamBox()
        let targets = RecordedSingleShutterTargets()

        let store = makeStore(
            streamBox: streamBox,
            persistTarget: { deviceId, target in
                await targets.record(deviceId: deviceId, target: target)
            }
        )
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 75, target: 75))

        let didObserve = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 75,
                pendingLocalTarget: nil
            )
        }

        #expect(didObserve)

        let didPersistClearedTarget = await waitUntilAsync {
            await targets.values() == [
                .init(deviceId: id10, target: nil)
            ]
        }
        #expect(didPersistClearedTarget)
    }

    @Test
    func sceneLikePositionOnlyCloseNeverExposesTargetOrGetsStuckMoving() async {
        let streamBox = DeviceStreamBox()

        let store = makeStore(streamBox: streamBox)
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 100, target: nil))
        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 100,
                pendingLocalTarget: nil
            )
        }
        #expect(didStart)

        streamBox.yield(makeShutter(identifier: id10, position: 80, target: nil))
        let didObserveFirstMove = await waitUntil {
            store.position == 80 && store.movingTarget == nil && !store.isMoving
        }
        #expect(didObserveFirstMove)

        streamBox.yield(makeShutter(identifier: id10, position: 40, target: nil))
        let didObserveSecondMove = await waitUntil {
            store.position == 40 && store.movingTarget == nil && !store.isMoving
        }
        #expect(didObserveSecondMove)

        streamBox.yield(makeShutter(identifier: id10, position: 0, target: nil))
        let didFinishClose = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 0,
                pendingLocalTarget: nil
            )
        }
        #expect(didFinishClose)

        #expect(store.movingTarget == nil)
        #expect(!store.isMoving)
        #expect(store.gaugePosition == ShutterPositionMapper.gaugePosition(from: 0))
    }

    @Test
    func observingPendingLocalTargetFromAnotherCardKeepsGaugeAndTargetSeparate() async {
        let streamBox = DeviceStreamBox()
        let sleepDurations = RecordedSleepDurations()
        let testTime = ManualTestClock()

        let store = makeStore(
            streamBox: streamBox,
            sleep: { duration in
                await sleepDurations.record(duration)
                try await testTime.sleep(for: duration)
            }
        )
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 100, target: nil))
        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 100,
                pendingLocalTarget: nil
            )
        }
        #expect(didStart)

        streamBox.yield(makeShutter(identifier: id10, position: 100, target: 0))

        let didObserveLocalTarget = await waitUntil {
            store.state == .shutterIsMovingToLocalTarget(
                deviceId: id10,
                position: 100,
                target: 0,
                ignoresNextMatchingPosition: true
            )
        }
        #expect(didObserveLocalTarget)
        #expect(store.gaugePosition == ShutterPositionMapper.gaugePosition(from: 100))
        #expect(store.movingTarget == 0)
        #expect(store.movementDirection == .closing)

        let didRecordTimeoutDuration = await waitUntilAsync {
            await sleepDurations.values() == [.seconds(60)]
        }
        #expect(didRecordTimeoutDuration)
    }

    @Test
    func externallyObservedMatchingEchoFrameCompletesOnSecondMatchingFrame() async {
        let streamBox = DeviceStreamBox()
        let targets = RecordedSingleShutterTargets()
        let timeoutLifecycle = TimeoutLifecycleRecorder()
        let testTime = ManualTestClock()

        let store = makeStore(
            streamBox: streamBox,
            sleep: { duration in
                await timeoutLifecycle.didStart()
                do {
                    try await testTime.sleep(for: duration)
                } catch {
                    await timeoutLifecycle.didCancel()
                    throw error
                }
            },
            persistTarget: { deviceId, target in
                await targets.record(deviceId: deviceId, target: target)
            }
        )
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 100, target: nil))
        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 100,
                pendingLocalTarget: nil
            )
        }
        #expect(didStart)

        streamBox.yield(makeShutter(identifier: id10, position: 100, target: 75))
        let didObserveTarget = await waitUntil {
            store.state == .shutterIsMovingToLocalTarget(
                deviceId: id10,
                position: 100,
                target: 75,
                ignoresNextMatchingPosition: true
            )
        }
        #expect(didObserveTarget)

        let timeoutStarted = await waitUntilAsync {
            await timeoutLifecycle.startCount() == 1
        }
        #expect(timeoutStarted)

        streamBox.yield(makeShutter(identifier: id10, position: 75, target: 75))
        let didIgnoreEchoFrame = await waitUntil {
            store.state == .shutterIsMovingToLocalTarget(
                deviceId: id10,
                position: 100,
                target: 75,
                ignoresNextMatchingPosition: false
            )
        }
        #expect(didIgnoreEchoFrame)

        streamBox.yield(makeShutter(identifier: id10, position: 75, target: 75))
        let didFinishMove = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 75,
                pendingLocalTarget: nil
            )
        }
        #expect(didFinishMove)

        let timeoutCancelled = await waitUntilAsync {
            await timeoutLifecycle.cancelCount() >= 1
        }
        #expect(timeoutCancelled)

        let didPersistClearedTarget = await waitUntilAsync {
            await targets.values() == [
                .init(deviceId: id10, target: nil)
            ]
        }
        #expect(didPersistClearedTarget)
    }

    @Test
    func targetWasSetInAppSendsCommandStartsTimeoutAndPersistsTarget() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedSingleShutterCommands()
        let targets = RecordedSingleShutterTargets()
        let sleepDurations = RecordedSleepDurations()
        let testTime = ManualTestClock()

        let store = makeStore(
            streamBox: streamBox,
            sendCommand: { deviceId, position in
                await commands.record(deviceId: deviceId, position: position)
            },
            sleep: { duration in
                await sleepDurations.record(duration)
                try await testTime.sleep(for: duration)
            },
            persistTarget: { deviceId, target in
                await targets.record(deviceId: deviceId, target: target)
            }
        )
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 20, target: nil))
        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 20,
                pendingLocalTarget: nil
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
            store.state == .shutterIsMovingToLocalTarget(
                deviceId: id10,
                position: 20,
                target: 75,
                ignoresNextMatchingPosition: true
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

        let didCaptureTimeoutTask = await waitUntil {
            store.state.timeoutTask != nil
        }
        #expect(didCaptureTimeoutTask)
    }

    @Test
    func retargetWhileMovingCancelsPreviousTimeoutAndStartsAnotherOne() async {
        let streamBox = DeviceStreamBox()
        let commands = RecordedSingleShutterCommands()
        let targets = RecordedSingleShutterTargets()
        let timeoutLifecycle = TimeoutLifecycleRecorder()
        let testTime = ManualTestClock()

        let store = makeStore(
            streamBox: streamBox,
            sendCommand: { deviceId, position in
                await commands.record(deviceId: deviceId, position: position)
            },
            sleep: { duration in
                await timeoutLifecycle.didStart()
                do {
                    try await testTime.sleep(for: duration)
                } catch {
                    await timeoutLifecycle.didCancel()
                    throw error
                }
            },
            persistTarget: { deviceId, target in
                await targets.record(deviceId: deviceId, target: target)
            }
        )
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 20, target: nil))
        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 20,
                pendingLocalTarget: nil
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
            store.state == .shutterIsMovingToLocalTarget(
                deviceId: id10,
                position: 20,
                target: 25,
                ignoresNextMatchingPosition: true
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
    func appInitiatedObservationShortSequenceClearsTargetWithoutTimeout() async {
        let streamBox = DeviceStreamBox()
        let targets = RecordedSingleShutterTargets()
        let timeoutLifecycle = TimeoutLifecycleRecorder()
        let testTime = ManualTestClock()

        let store = makeStore(
            streamBox: streamBox,
            sleep: { duration in
                await timeoutLifecycle.didStart()
                do {
                    try await testTime.sleep(for: duration)
                } catch {
                    await timeoutLifecycle.didCancel()
                    throw error
                }
            },
            persistTarget: { deviceId, target in
                await targets.record(deviceId: deviceId, target: target)
            }
        )
        store.start()

        streamBox.yield(makeShutter(identifier: id10, position: 100, target: nil))
        let didStart = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 100,
                pendingLocalTarget: nil
            )
        }
        #expect(didStart)

        store.send(.targetWasSetInApp(target: 75))

        streamBox.yield(makeShutter(identifier: id10, position: 100, target: 75))
        let didObservePendingTarget = await waitUntil {
            store.state == .shutterIsMovingToLocalTarget(
                deviceId: id10,
                position: 100,
                target: 75,
                ignoresNextMatchingPosition: true
            )
        }
        #expect(didObservePendingTarget)

        streamBox.yield(makeShutter(identifier: id10, position: 90, target: 75))
        let didObserveProgress = await waitUntil {
            store.state == .shutterIsMovingToLocalTarget(
                deviceId: id10,
                position: 90,
                target: 75,
                ignoresNextMatchingPosition: false
            )
        }
        #expect(didObserveProgress)

        streamBox.yield(makeShutter(identifier: id10, position: 75, target: 75))
        let didFinishMove = await waitUntil {
            store.state == .featureIsStarted(
                deviceId: id10,
                position: 75,
                pendingLocalTarget: nil
            )
        }
        #expect(didFinishMove)

        let timeoutCancelled = await waitUntilAsync {
            await timeoutLifecycle.cancelCount() >= 1
        }
        #expect(timeoutCancelled)

        let didPersistTargetLifecycle = await waitUntilAsync {
            let persistedTargets = await targets.values()
            return persistedTargets.contains(.init(deviceId: id10, target: 75))
                && persistedTargets.contains(.init(deviceId: id10, target: nil))
        }
        #expect(didPersistTargetLifecycle)
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

    private func makeStore(
        streamBox: DeviceStreamBox,
        sendCommand: @escaping @Sendable (DeviceIdentifier, Int) async -> Void = { _, _ in },
        sleep: (@Sendable (Duration) async throws -> Void)? = nil,
        persistTarget: @escaping @Sendable (DeviceIdentifier, Int?) async -> Void = { _, _ in }
    ) -> SingleShutterStore {
        let testTime = ManualTestClock()
        return SingleShutterStore(
            deviceId: id10,
            observeDevice: .init(
                observeDevice: { _ in streamBox.stream }
            ),
            sendCommand: .init(
                sendCommand: sendCommand
            ),
            startTimeout: .init(
                sleep: sleep ?? { duration in
                    try await testTime.sleep(for: duration)
                }
            ),
            persistTarget: .init(
                persistTarget: persistTarget
            )
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
