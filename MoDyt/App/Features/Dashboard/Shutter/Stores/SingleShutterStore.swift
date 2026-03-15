import Foundation
import Observation

enum SingleShutterMovementDirection: Sendable, Equatable {
    case idle
    case opening
    case closing
}

enum SingleShutterState: Sendable {
    private static let movementCompletionTolerance = 3

    case featureIsIdle(deviceId: DeviceIdentifier, position: Int, pendingLocalTarget: Int?)
    case featureIsStarted(deviceId: DeviceIdentifier, position: Int, pendingLocalTarget: Int?)
    case shutterIsMovingToLocalTarget(
        deviceId: DeviceIdentifier,
        position: Int,
        target: Int,
        timeoutTask: Task<Void, Never>? = nil,
        ignoresNextMatchingPosition: Bool = false
    )

    var deviceId: DeviceIdentifier {
        switch self {
        case .featureIsIdle(let deviceId, _, _),
             .featureIsStarted(let deviceId, _, _),
             .shutterIsMovingToLocalTarget(let deviceId, _, _, _, _):
            return deviceId
        }
    }

    var position: Int {
        switch self {
        case .featureIsIdle(_, let position, _),
             .featureIsStarted(_, let position, _),
             .shutterIsMovingToLocalTarget(_, let position, _, _, _):
            return position
        }
    }

    var target: Int? {
        switch self {
        case .featureIsIdle(_, _, let pendingLocalTarget),
             .featureIsStarted(_, _, let pendingLocalTarget):
            return pendingLocalTarget
        case .shutterIsMovingToLocalTarget(_, _, let target, _, _):
            return target
        }
    }

    var movingTarget: Int? {
        if case .shutterIsMovingToLocalTarget(_, _, let target, _, _) = self {
            return target
        }
        return nil
    }

    var timeoutTask: Task<Void, Never>? {
        if case .shutterIsMovingToLocalTarget(_, _, _, let timeoutTask, _) = self {
            return timeoutTask
        }
        return nil
    }

    var gaugePosition: Int {
        switch self {
        case .featureIsIdle:
            return 0
        case .featureIsStarted(_, let position, _),
             .shutterIsMovingToLocalTarget(_, let position, _, _, _):
            return ShutterPositionMapper.gaugePosition(from: position)
        }
    }

    var destinationGaugePosition: Int? {
        guard case .shutterIsMovingToLocalTarget(_, let position, let target, _, _) = self,
              abs(position - target) > Self.movementCompletionTolerance else {
            return nil
        }

        return ShutterPositionMapper.gaugePosition(from: target)
    }

    var movementDirection: SingleShutterMovementDirection {
        guard case .shutterIsMovingToLocalTarget(_, let position, let target, _, _) = self,
              abs(position - target) > Self.movementCompletionTolerance else {
            return .idle
        }

        return target > position ? .opening : .closing
    }

    var isUserInitiatedMovement: Bool {
        if case .shutterIsMovingToLocalTarget = self {
            return true
        }

        return false
    }

    var isMovingInApp: Bool {
        if case .shutterIsMovingToLocalTarget = self {
            return true
        }

        return false
    }
}

extension SingleShutterState: Equatable {
    static func == (lhs: SingleShutterState, rhs: SingleShutterState) -> Bool {
        switch (lhs, rhs) {
        case let (
            .featureIsIdle(lhsDeviceId, lhsPosition, lhsPendingLocalTarget),
            .featureIsIdle(rhsDeviceId, rhsPosition, rhsPendingLocalTarget)
        ):
            return lhsDeviceId == rhsDeviceId
                && lhsPosition == rhsPosition
                && lhsPendingLocalTarget == rhsPendingLocalTarget

        case let (
            .featureIsStarted(lhsDeviceId, lhsPosition, lhsPendingLocalTarget),
            .featureIsStarted(rhsDeviceId, rhsPosition, rhsPendingLocalTarget)
        ):
            return lhsDeviceId == rhsDeviceId
                && lhsPosition == rhsPosition
                && lhsPendingLocalTarget == rhsPendingLocalTarget

        case let (
            .shutterIsMovingToLocalTarget(
                lhsDeviceId,
                lhsPosition,
                lhsTarget,
                _,
                lhsIgnoresNextMatchingPosition
            ),
            .shutterIsMovingToLocalTarget(
                rhsDeviceId,
                rhsPosition,
                rhsTarget,
                _,
                rhsIgnoresNextMatchingPosition
            )
        ):
            return lhsDeviceId == rhsDeviceId
                && lhsPosition == rhsPosition
                && lhsTarget == rhsTarget
                && lhsIgnoresNextMatchingPosition == rhsIgnoresNextMatchingPosition

        default:
            return false
        }
    }
}

enum SingleShutterEvent: Sendable {
    case positionWasReceived(position: Int)
    case pendingLocalTargetWasObserved(target: Int?)
    case targetWasSetInApp(target: Int)
    case timeoutHasExpired
    case timeoutTaskWasCreated(task: Task<Void, Never>)
}

extension SingleShutterEvent: Equatable {
    static func == (lhs: SingleShutterEvent, rhs: SingleShutterEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.positionWasReceived(lhsPosition), .positionWasReceived(rhsPosition)):
            return lhsPosition == rhsPosition

        case let (.pendingLocalTargetWasObserved(lhsTarget), .pendingLocalTargetWasObserved(rhsTarget)):
            return lhsTarget == rhsTarget

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

        static func reduce(
            _ state: SingleShutterState,
            _ event: SingleShutterEvent
        ) -> Transition<SingleShutterState, SingleShutterEffect> {
            switch (state, event) {
            case let (.featureIsIdle(deviceId, _, pendingLocalTarget), .positionWasReceived(position)):
                return reduceKnownPositionWithOptionalTarget(
                    deviceId: deviceId,
                    position: position,
                    target: pendingLocalTarget
                )

            case let (.featureIsIdle(deviceId, position, _), .pendingLocalTargetWasObserved(target)):
                return .init(
                    state: .featureIsIdle(
                        deviceId: deviceId,
                        position: position,
                        pendingLocalTarget: target
                    )
                )

            case let (.featureIsStarted(deviceId, _, pendingLocalTarget), .positionWasReceived(position)):
                return reduceKnownPositionWithOptionalTarget(
                    deviceId: deviceId,
                    position: position,
                    target: pendingLocalTarget
                )

            case let (.featureIsStarted(deviceId, position, _), .pendingLocalTargetWasObserved(target)):
                return reduceKnownPositionWithOptionalTarget(
                    deviceId: deviceId,
                    position: position,
                    target: target
                )

            case let (.featureIsStarted(deviceId, position, _), .targetWasSetInApp(newTarget)):
                guard !Self.hasReachedTarget(position: position, target: newTarget) else {
                    return .init(
                        state: .featureIsStarted(
                            deviceId: deviceId,
                            position: position,
                            pendingLocalTarget: nil
                        ),
                        effects: [.sendCommand(deviceId: deviceId, position: newTarget)]
                    )
                }

                return .init(
                    state: .shutterIsMovingToLocalTarget(
                        deviceId: deviceId,
                        position: position,
                        target: newTarget,
                        timeoutTask: nil,
                        ignoresNextMatchingPosition: true
                    ),
                    effects: [
                        .sendCommand(deviceId: deviceId, position: newTarget),
                        .startTimeout,
                        .persistTarget(deviceId: deviceId, target: newTarget),
                    ]
                )

            case let (
                .shutterIsMovingToLocalTarget(deviceId, position, oldTarget, timeoutTask, _),
                .targetWasSetInApp(newTarget)
            ) where newTarget != oldTarget:
                guard !Self.hasReachedTarget(position: position, target: newTarget) else {
                    return .init(
                        state: .featureIsStarted(
                            deviceId: deviceId,
                            position: position,
                            pendingLocalTarget: nil
                        ),
                        effects: [
                            .cancelTimeout(task: timeoutTask),
                            .sendCommand(deviceId: deviceId, position: newTarget),
                            .persistTarget(deviceId: deviceId, target: nil),
                        ]
                    )
                }

                return .init(
                    state: .shutterIsMovingToLocalTarget(
                        deviceId: deviceId,
                        position: position,
                        target: newTarget,
                        timeoutTask: nil,
                        ignoresNextMatchingPosition: true
                    ),
                    effects: [
                        .cancelTimeout(task: timeoutTask),
                        .sendCommand(deviceId: deviceId, position: newTarget),
                        .startTimeout,
                        .persistTarget(deviceId: deviceId, target: newTarget),
                    ]
                )

            case let (
                .shutterIsMovingToLocalTarget(deviceId, position, oldTarget, timeoutTask, _),
                .pendingLocalTargetWasObserved(target)
            ):
                guard target != oldTarget else {
                    return .init(state: state)
                }

                if let target {
                    guard !Self.hasReachedTarget(position: position, target: target) else {
                        return .init(
                            state: .featureIsStarted(
                                deviceId: deviceId,
                                position: position,
                                pendingLocalTarget: nil
                            ),
                            effects: [
                                .cancelTimeout(task: timeoutTask),
                                .persistTarget(deviceId: deviceId, target: nil),
                            ]
                        )
                    }

                    return .init(
                        state: .shutterIsMovingToLocalTarget(
                            deviceId: deviceId,
                            position: position,
                            target: target,
                            timeoutTask: nil,
                            ignoresNextMatchingPosition: true
                        ),
                        effects: [
                            .cancelTimeout(task: timeoutTask),
                            .startTimeout,
                        ]
                    )
                }

                return .init(
                    state: .featureIsStarted(
                        deviceId: deviceId,
                        position: position,
                        pendingLocalTarget: nil
                    ),
                    effects: [.cancelTimeout(task: timeoutTask)]
                )

            case let (
                .shutterIsMovingToLocalTarget(
                    deviceId,
                    oldPosition,
                    target,
                    timeoutTask,
                    ignoresNextMatchingPosition
                ),
                .positionWasReceived(newPosition)
            ):
                if ignoresNextMatchingPosition,
                   Self.hasReachedTarget(position: newPosition, target: target) {
                    return .init(
                        state: .shutterIsMovingToLocalTarget(
                            deviceId: deviceId,
                            position: oldPosition,
                            target: target,
                            timeoutTask: timeoutTask,
                            ignoresNextMatchingPosition: false
                        )
                    )
                }

                if Self.hasReachedTarget(position: newPosition, target: target) {
                    return .init(
                        state: .featureIsStarted(
                            deviceId: deviceId,
                            position: newPosition,
                            pendingLocalTarget: nil
                        ),
                        effects: [
                            .cancelTimeout(task: timeoutTask),
                            .persistTarget(deviceId: deviceId, target: nil),
                        ]
                    )
                }

                return .init(
                    state: .shutterIsMovingToLocalTarget(
                        deviceId: deviceId,
                        position: newPosition,
                        target: target,
                        timeoutTask: timeoutTask,
                        ignoresNextMatchingPosition: false
                    )
                )

            case let (.shutterIsMovingToLocalTarget(deviceId, position, _, timeoutTask, _), .timeoutHasExpired):
                return .init(
                    state: .featureIsStarted(
                        deviceId: deviceId,
                        position: position,
                        pendingLocalTarget: nil
                    ),
                    effects: [
                        .cancelTimeout(task: timeoutTask),
                        .persistTarget(deviceId: deviceId, target: nil),
                    ]
                )

            case let (
                .shutterIsMovingToLocalTarget(
                    deviceId,
                    position,
                    target,
                    _,
                    ignoresNextMatchingPosition
                ),
                .timeoutTaskWasCreated(timeoutTask)
            ):
                return .init(
                    state: .shutterIsMovingToLocalTarget(
                        deviceId: deviceId,
                        position: position,
                        target: target,
                        timeoutTask: timeoutTask,
                        ignoresNextMatchingPosition: ignoresNextMatchingPosition
                    )
                )

            default:
                return .init(state: state)
            }
        }

        private static func reduceKnownPositionWithOptionalTarget(
            deviceId: DeviceIdentifier,
            position: Int,
            target: Int?
        ) -> Transition<SingleShutterState, SingleShutterEffect> {
            guard let target else {
                return .init(
                    state: .featureIsStarted(
                        deviceId: deviceId,
                        position: position,
                        pendingLocalTarget: nil
                    )
                )
            }

            guard !Self.hasReachedTarget(position: position, target: target) else {
                return .init(
                    state: .featureIsStarted(
                        deviceId: deviceId,
                        position: position,
                        pendingLocalTarget: nil
                    ),
                    effects: [.persistTarget(deviceId: deviceId, target: nil)]
                )
            }

            return .init(
                state: .shutterIsMovingToLocalTarget(
                    deviceId: deviceId,
                    position: position,
                    target: target,
                    timeoutTask: nil,
                    ignoresNextMatchingPosition: true
                ),
                effects: [.startTimeout]
            )
        }

        private static func hasReachedTarget(position: Int, target: Int) -> Bool {
            abs(position - target) <= completionTolerance
        }
    }

    private(set) var state: SingleShutterState = .featureIsIdle(
        deviceId: .init(deviceId: 0, endpointId: 0),
        position: 0,
        pendingLocalTarget: nil
    )

    private let deviceId: DeviceIdentifier
    private let observeDevice: ObserveSingleShutterEffectExecutor
    private let sendCommand: SendSingleShutterCommandEffectExecutor
    private let startTimeout: StartSingleShutterTimeoutEffectExecutor
    private let persistTarget: PersistSingleShutterTargetEffectExecutor
    private var observationTask: Task<Void, Never>?
    private var hasStarted = false

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
        deviceId: DeviceIdentifier,
        observeDevice: ObserveSingleShutterEffectExecutor,
        sendCommand: SendSingleShutterCommandEffectExecutor,
        startTimeout: StartSingleShutterTimeoutEffectExecutor,
        persistTarget: PersistSingleShutterTargetEffectExecutor
    ) {
        self.deviceId = deviceId
        self.observeDevice = observeDevice
        self.sendCommand = sendCommand
        self.startTimeout = startTimeout
        self.persistTarget = persistTarget
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let deviceId = self.deviceId
        self.state = .featureIsIdle(
            deviceId: deviceId,
            position: 0,
            pendingLocalTarget: nil
        )
        replaceTask(
            &observationTask,
            with: makeTrackedStreamTask(
                operation: { [deviceId, observeDevice] in
                    await observeDevice(deviceId)
                },
                onEvent: { [weak self] event in
                    self?.send(event)
                },
                onFinish: { [weak self] in
                    self?.observationTask = nil
                }
            )
        )
    }

    isolated deinit {
        observationTask?.cancel()
    }

    func send(_ event: SingleShutterEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [SingleShutterEffect]) {
        for effect in effects {
            switch effect {
            case .cancelTimeout(let timeoutTask):
                timeoutTask?.cancel()

            case .sendCommand(let deviceId, let position):
                launchFireAndForgetTask { [sendCommand] in
                    await sendCommand(
                        deviceId: deviceId,
                        position: position
                    )
                }

            case .startTimeout:
                startTimeoutIfNeeded()

            case .persistTarget(let deviceId, let target):
                launchFireAndForgetTask { [persistTarget] in
                    await persistTarget(
                        deviceId: deviceId,
                        target: target
                    )
                }
            }
        }
    }

    private func startTimeoutIfNeeded() {
        guard case .shutterIsMovingToLocalTarget = state else {
            return
        }

        let timeoutTask = makeTrackedEventTask(
            operation: { [startTimeout] in
                await startTimeout()
            },
            onEvent: { [weak self] event in
                self?.send(event)
            }
        )

        send(.timeoutTaskWasCreated(task: timeoutTask))
    }
}
