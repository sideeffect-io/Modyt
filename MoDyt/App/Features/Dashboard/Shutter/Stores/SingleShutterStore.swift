import Foundation
import Observation

enum SingleShutterMovementDirection: Sendable, Equatable {
    case idle
    case opening
    case closing
}

enum SingleShutterState: Sendable {
    private static let movementCompletionTolerance = 3

    case featureIsIdle(deviceId: DeviceIdentifier, position: Int, target: Int?)
    case featureIsStarted(deviceId: DeviceIdentifier, position: Int, target: Int?)
    case shutterIsMovingInApp(
        deviceId: DeviceIdentifier,
        position: Int,
        target: Int,
        timeoutTask: Task<Void, Never>? = nil,
        receivedValueCountAfterInAppTarget: Int? = nil
    )

    var deviceId: DeviceIdentifier {
        switch self {
        case .featureIsIdle(let deviceId, _, _),
             .featureIsStarted(let deviceId, _, _),
             .shutterIsMovingInApp(let deviceId, _, _, _, _):
            return deviceId
        }
    }

    var position: Int {
        switch self {
        case .featureIsIdle(_, let position, _),
             .featureIsStarted(_, let position, _),
             .shutterIsMovingInApp(_, let position, _, _, _):
            return position
        }
    }

    var target: Int? {
        switch self {
        case .featureIsIdle(_, _, let target),
             .featureIsStarted(_, _, let target):
            return target
        case .shutterIsMovingInApp(_, _, let target, _, _):
            return target
        }
    }

    var movingTarget: Int? {
        if case .shutterIsMovingInApp(_, _, let target, _, _) = self {
            return target
        }
        return nil
    }

    var timeoutTask: Task<Void, Never>? {
        if case .shutterIsMovingInApp(_, _, _, let timeoutTask, _) = self {
            return timeoutTask
        }
        return nil
    }

    var gaugePosition: Int {
        switch self {
        case .featureIsIdle:
            return 0
        case .featureIsStarted(_, let position, _):
            return ShutterPositionMapper.gaugePosition(from: position)
        case .shutterIsMovingInApp(_, let position, _, _, _):
            return ShutterPositionMapper.gaugePosition(from: position)
        }
    }

    var destinationGaugePosition: Int? {
        guard case .shutterIsMovingInApp(_, let position, let target, _, _) = self,
              abs(position - target) > Self.movementCompletionTolerance else {
            return nil
        }
        return ShutterPositionMapper.gaugePosition(from: target)
    }

    var movementDirection: SingleShutterMovementDirection {
        guard case .shutterIsMovingInApp(_, let position, let target, _, _) = self,
              abs(position - target) > Self.movementCompletionTolerance else {
            return .idle
        }

        return target > position ? .opening : .closing
    }

    var isUserInitiatedMovement: Bool {
        if case .shutterIsMovingInApp(_, _, _, _, .some) = self {
            return true
        }

        return false
    }

    var isMovingInApp: Bool {
        if case .shutterIsMovingInApp = self {
            return true
        }
        return false
    }
}

extension SingleShutterState: Equatable {
    static func == (lhs: SingleShutterState, rhs: SingleShutterState) -> Bool {
        switch (lhs, rhs) {
        case let (
            .featureIsIdle(lhsDeviceId, lhsPosition, lhsTarget),
            .featureIsIdle(rhsDeviceId, rhsPosition, rhsTarget)
        ):
            return lhsDeviceId == rhsDeviceId
                && lhsPosition == rhsPosition
                && lhsTarget == rhsTarget

        case let (
            .featureIsStarted(lhsDeviceId, lhsPosition, lhsTarget),
            .featureIsStarted(rhsDeviceId, rhsPosition, rhsTarget)
        ):
            return lhsDeviceId == rhsDeviceId
                && lhsPosition == rhsPosition
                && lhsTarget == rhsTarget

        case let (
            .shutterIsMovingInApp(lhsDeviceId, lhsPosition, lhsTarget, _, lhsReceivedValueCount),
            .shutterIsMovingInApp(rhsDeviceId, rhsPosition, rhsTarget, _, rhsReceivedValueCount)
        ):
            return lhsDeviceId == rhsDeviceId
                && lhsPosition == rhsPosition
                && lhsTarget == rhsTarget
                && lhsReceivedValueCount == rhsReceivedValueCount

        default:
            return false
        }
    }
}

enum SingleShutterEvent: Sendable {
    case valueWasReceived(position: Int, target: Int?)
    case targetWasSetInApp(target: Int)
    case timeoutHasExpired
    case timeoutTaskWasCreated(task: Task<Void, Never>)
}

extension SingleShutterEvent: Equatable {
    static func == (lhs: SingleShutterEvent, rhs: SingleShutterEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.valueWasReceived(lhsPosition, lhsTarget), .valueWasReceived(rhsPosition, rhsTarget)):
            return lhsPosition == rhsPosition && lhsTarget == rhsTarget

        case let (.targetWasSetInApp(lhsTarget), .targetWasSetInApp(rhsTarget)):
            return lhsTarget == rhsTarget

        case (.timeoutHasExpired, .timeoutHasExpired):
            return true

        case (.timeoutTaskWasCreated, .timeoutTaskWasCreated):
            return true

        default:
            return false
        }
    }
}

enum SingleShutterEffect: Sendable {
    case cancelTimeout(task: Task<Void, Never>?)
    case sendCommand(deviceId: DeviceIdentifier, position: Int)
    case startTimeout
    case persistTarget(deviceId: DeviceIdentifier, target: Int?)
}

extension SingleShutterEffect: Equatable {
    static func == (lhs: SingleShutterEffect, rhs: SingleShutterEffect) -> Bool {
        switch (lhs, rhs) {
        case (.cancelTimeout(task: _), .cancelTimeout(task: _)):
            return true

        case let (
            .sendCommand(lhsDeviceId, lhsPosition),
            .sendCommand(rhsDeviceId, rhsPosition)
        ):
            return lhsDeviceId == rhsDeviceId && lhsPosition == rhsPosition

        case (.startTimeout, .startTimeout):
            return true

        case let (
            .persistTarget(lhsDeviceId, lhsTarget),
            .persistTarget(rhsDeviceId, rhsTarget)
        ):
            return lhsDeviceId == rhsDeviceId && lhsTarget == rhsTarget

        default:
            return false
        }
    }
}

@Observable
@MainActor
final class SingleShutterStore: StartableStore {
    struct StateMachine {
        private static let completionTolerance = 3

        var state: SingleShutterState = .featureIsIdle(
            deviceId: .init(deviceId: 0, endpointId: 0),
            position: 0,
            target: nil
        )

        mutating func reduce(_ event: SingleShutterEvent) -> [SingleShutterEffect] {
            switch (state, event) {
            case let (.featureIsIdle(deviceId, _, _), .valueWasReceived(position, target)):
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    target: target
                )
                return []

            case let (.featureIsStarted(deviceId, oldPosition, oldTarget), .valueWasReceived(newPosition, newTarget)):
                if newTarget == nil, newPosition != oldPosition {
                    state = .featureIsStarted(
                        deviceId: deviceId,
                        position: newPosition,
                        target: nil
                    )
                    return []
                }

                if let newTarget, newTarget != oldTarget {
                    state = .shutterIsMovingInApp(
                        deviceId: deviceId,
                        position: newPosition,
                        target: newTarget,
                        timeoutTask: nil,
                        receivedValueCountAfterInAppTarget: 1
                    )
                    return [.startTimeout]
                }

                if newTarget == oldTarget, newPosition != oldPosition {
                    state = .featureIsStarted(
                        deviceId: deviceId,
                        position: newPosition,
                        target: newTarget
                    )
                    return []
                }

                return []

            case let (.featureIsStarted(deviceId, position, _), .targetWasSetInApp(newTarget)):
                state = .shutterIsMovingInApp(
                    deviceId: deviceId,
                    position: position,
                    target: newTarget,
                    timeoutTask: nil,
                    receivedValueCountAfterInAppTarget: 0
                )
                return [
                    .sendCommand(deviceId: deviceId, position: newTarget),
                    .startTimeout,
                    .persistTarget(deviceId: deviceId, target: newTarget),
                ]

            case let (
                .shutterIsMovingInApp(deviceId, position, oldTarget, timeoutTask, _),
                .targetWasSetInApp(newTarget)
            ) where newTarget != oldTarget:
                state = .shutterIsMovingInApp(
                    deviceId: deviceId,
                    position: position,
                    target: newTarget,
                    timeoutTask: nil,
                    receivedValueCountAfterInAppTarget: 0
                )
                return [
                    .cancelTimeout(task: timeoutTask),
                    .sendCommand(deviceId: deviceId, position: newTarget),
                    .startTimeout,
                    .persistTarget(deviceId: deviceId, target: newTarget),
                ]

            case let (
                .shutterIsMovingInApp(
                    deviceId,
                    oldPosition,
                    oldTarget,
                    timeoutTask,
                    receivedValueCountAfterInAppTarget
                ),
                .valueWasReceived(newPosition, newTarget)
            ):
                let nextReceivedValueCount = receivedValueCountAfterInAppTarget.map { $0 + 1 }

                if let nextReceivedValueCount {
                    let position = nextReceivedValueCount == 2
                        ? oldPosition
                        : newPosition

                    state = .shutterIsMovingInApp(
                        deviceId: deviceId,
                        position: position,
                        target: oldTarget,
                        timeoutTask: timeoutTask,
                        receivedValueCountAfterInAppTarget: nextReceivedValueCount
                    )

                    if nextReceivedValueCount == 2 {
                        return []
                    }
                }

                if newTarget != oldTarget {
                    if let newTarget {
                        if Self.hasReachedTarget(position: newPosition, target: newTarget) {
                            state = .featureIsStarted(
                                deviceId: deviceId,
                                position: newPosition,
                                target: nil
                            )
                            return [
                                .cancelTimeout(task: timeoutTask),
                                .persistTarget(deviceId: deviceId, target: nil),
                            ]
                        }

                        state = .shutterIsMovingInApp(
                            deviceId: deviceId,
                            position: newPosition,
                            target: newTarget,
                            timeoutTask: nil,
                            receivedValueCountAfterInAppTarget: nextReceivedValueCount
                        )
                        return [
                            .cancelTimeout(task: timeoutTask),
                            .startTimeout,
                        ]
                    }

                    return []
                }

                if newTarget == oldTarget,
                   Self.hasReachedTarget(position: newPosition, target: oldTarget) {
                    state = .featureIsStarted(
                        deviceId: deviceId,
                        position: newPosition,
                        target: nil
                    )
                    return [
                        .cancelTimeout(task: timeoutTask),
                        .persistTarget(deviceId: deviceId, target: nil),
                    ]
                }

                return []

            case let (.shutterIsMovingInApp(deviceId, position, _, timeoutTask, _), .timeoutHasExpired):
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    target: nil
                )
                return [
                    .cancelTimeout(task: timeoutTask),
                    .persistTarget(deviceId: deviceId, target: nil),
                ]

            case let (
                .shutterIsMovingInApp(
                    deviceId,
                    position,
                    target,
                    _,
                    receivedValueCountAfterInAppTarget
                ),
                .timeoutTaskWasCreated(timeoutTask)
            ):
                state = .shutterIsMovingInApp(
                    deviceId: deviceId,
                    position: position,
                    target: target,
                    timeoutTask: timeoutTask,
                    receivedValueCountAfterInAppTarget: receivedValueCountAfterInAppTarget
                )
                return []

            default:
                return []
            }
        }

        private static func hasReachedTarget(position: Int, target: Int) -> Bool {
            abs(position - target) <= completionTolerance
        }
    }

    struct Dependencies {
        let observeDevice: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        let sendCommand: @Sendable (DeviceIdentifier, Int) async -> Void
        let sleep: @Sendable (Duration) async throws -> Void
        let persistTarget: @Sendable (DeviceIdentifier, Int?) async -> Void

        init(
            observeDevice: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable,
            sendCommand: @escaping @Sendable (DeviceIdentifier, Int) async -> Void,
            sleep: @escaping @Sendable (Duration) async throws -> Void,
            persistTarget: @escaping @Sendable (DeviceIdentifier, Int?) async -> Void
        ) {
            self.observeDevice = observeDevice
            self.sendCommand = sendCommand
            self.sleep = sleep
            self.persistTarget = persistTarget
        }
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: SingleShutterState {
        stateMachine.state
    }

    private let deviceId: DeviceIdentifier
    private let dependencies: Dependencies
    private let observationTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    private static let timeoutDuration: Duration = .seconds(60)

    var position: Int {
        state.position
    }

    var gaugePosition: Int {
        state.gaugePosition
    }

    var destinationGaugePosition: Int? {
        state.destinationGaugePosition
    }

    var target: Int? {
        state.target
    }

    var movingTarget: Int? {
        state.movingTarget
    }

    var isGaugeDimmed: Bool {
        true
    }

    var isMovingInApp: Bool {
        state.isMovingInApp
    }

    var movementDirection: SingleShutterMovementDirection {
        state.movementDirection
    }

    var isMoving: Bool {
        state.isMovingInApp
    }

    var isUserInitiatedMovement: Bool {
        state.isUserInitiatedMovement
    }

    init(
        dependencies: Dependencies,
        deviceId: DeviceIdentifier
    ) {
        self.deviceId = deviceId
        self.dependencies = dependencies
        self.worker = Worker(
            observeDevice: dependencies.observeDevice,
            sendCommand: dependencies.sendCommand,
            persistTarget: dependencies.persistTarget
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let deviceId = self.deviceId
        self.stateMachine = StateMachine(state: .featureIsIdle(deviceId: deviceId, position: 0, target: nil))
        observationTask.task = Task { [weak self, worker] in
            await worker.observe(deviceId: deviceId) { [weak self] values in
                await self?.send(
                    .valueWasReceived(
                        position: values.position,
                        target: values.target
                    )
                )
            }
        }
    }

    deinit {
        observationTask.cancel()
    }

    func send(_ event: SingleShutterEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    private func handle(_ effects: [SingleShutterEffect]) {
        for effect in effects {
            switch effect {
            case .cancelTimeout(let timeoutTask):
                timeoutTask?.cancel()

            case .sendCommand(let deviceId, let position):
                Task { [worker] in
                    await worker.sendCommand(deviceId: deviceId, position: position)
                }

            case .startTimeout:
                startTimeoutIfNeeded()

            case .persistTarget(let deviceId, let target):
                Task { [worker] in
                    await worker.persistTarget(deviceId: deviceId, target: target)
                }
            }
        }
    }

    private func startTimeoutIfNeeded() {
        guard case .shutterIsMovingInApp = state else {
            return
        }

        let timeoutTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                try await dependencies.sleep(Self.timeoutDuration)
                self.send(.timeoutHasExpired)
            } catch {
                return
            }
        }

        send(.timeoutTaskWasCreated(task: timeoutTask))
    }

    private actor Worker {
        private let observeDeviceSource: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        private let sendCommandAction: @Sendable (DeviceIdentifier, Int) async -> Void
        private let persistTargetAction: @Sendable (DeviceIdentifier, Int?) async -> Void

        init(
            observeDevice: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable,
            sendCommand: @escaping @Sendable (DeviceIdentifier, Int) async -> Void,
            persistTarget: @escaping @Sendable (DeviceIdentifier, Int?) async -> Void
        ) {
            self.observeDeviceSource = observeDevice
            self.sendCommandAction = sendCommand
            self.persistTargetAction = persistTarget
        }

        func observe(
            deviceId: DeviceIdentifier,
            onValues: @escaping @Sendable ((position: Int, target: Int?)) async -> Void
        ) async {
            let stream = await observeDeviceSource(deviceId)
            var previousValues: (position: Int, target: Int?)?

            for await device in stream {
                guard !Task.isCancelled else { return }
                let values = (
                    position: device?.shutterPosition ?? 0,
                    target: device?.shutterTargetPosition
                )

                if let previousValues {
                    guard previousValues.position != values.position
                            || previousValues.target != values.target else {
                        continue
                    }
                }

                await onValues(values)
                previousValues = values
            }
        }

        func sendCommand(deviceId: DeviceIdentifier, position: Int) async {
            await sendCommandAction(deviceId, position)
        }

        func persistTarget(deviceId: DeviceIdentifier, target: Int?) async {
            await persistTargetAction(deviceId, target)
        }
    }
}
