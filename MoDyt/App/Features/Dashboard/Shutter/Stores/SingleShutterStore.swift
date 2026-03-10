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

        var state: SingleShutterState = .featureIsIdle(
            deviceId: .init(deviceId: 0, endpointId: 0),
            position: 0,
            pendingLocalTarget: nil
        )

        mutating func reduce(_ event: SingleShutterEvent) -> [SingleShutterEffect] {
            switch (state, event) {
            case let (.featureIsIdle(deviceId, _, pendingLocalTarget), .positionWasReceived(position)):
                return reducePositionWhileIdle(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: pendingLocalTarget
                )

            case let (.featureIsIdle(deviceId, position, _), .pendingLocalTargetWasObserved(target)):
                state = .featureIsIdle(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: target
                )
                return []

            case let (.featureIsStarted(deviceId, _, pendingLocalTarget), .positionWasReceived(position)):
                return reducePositionWhileStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: pendingLocalTarget
                )

            case let (.featureIsStarted(deviceId, position, _), .pendingLocalTargetWasObserved(target)):
                return reduceObservedPendingLocalTarget(
                    deviceId: deviceId,
                    position: position,
                    target: target
                )

            case let (.featureIsStarted(deviceId, position, _), .targetWasSetInApp(newTarget)):
                guard !Self.hasReachedTarget(position: position, target: newTarget) else {
                    state = .featureIsStarted(
                        deviceId: deviceId,
                        position: position,
                        pendingLocalTarget: nil
                    )
                    return [.sendCommand(deviceId: deviceId, position: newTarget)]
                }

                state = .shutterIsMovingToLocalTarget(
                    deviceId: deviceId,
                    position: position,
                    target: newTarget,
                    timeoutTask: nil,
                    ignoresNextMatchingPosition: true
                )
                return [
                    .sendCommand(deviceId: deviceId, position: newTarget),
                    .startTimeout,
                    .persistTarget(deviceId: deviceId, target: newTarget),
                ]

            case let (
                .shutterIsMovingToLocalTarget(deviceId, position, oldTarget, timeoutTask, _),
                .targetWasSetInApp(newTarget)
            ) where newTarget != oldTarget:
                guard !Self.hasReachedTarget(position: position, target: newTarget) else {
                    state = .featureIsStarted(
                        deviceId: deviceId,
                        position: position,
                        pendingLocalTarget: nil
                    )
                    return [
                        .cancelTimeout(task: timeoutTask),
                        .sendCommand(deviceId: deviceId, position: newTarget),
                        .persistTarget(deviceId: deviceId, target: nil),
                    ]
                }

                state = .shutterIsMovingToLocalTarget(
                    deviceId: deviceId,
                    position: position,
                    target: newTarget,
                    timeoutTask: nil,
                    ignoresNextMatchingPosition: true
                )
                return [
                    .cancelTimeout(task: timeoutTask),
                    .sendCommand(deviceId: deviceId, position: newTarget),
                    .startTimeout,
                    .persistTarget(deviceId: deviceId, target: newTarget),
                ]

            case let (
                .shutterIsMovingToLocalTarget(deviceId, position, oldTarget, timeoutTask, _),
                .pendingLocalTargetWasObserved(target)
            ):
                guard target != oldTarget else {
                    return []
                }

                if let target {
                    guard !Self.hasReachedTarget(position: position, target: target) else {
                        state = .featureIsStarted(
                            deviceId: deviceId,
                            position: position,
                            pendingLocalTarget: nil
                        )
                        return [
                            .cancelTimeout(task: timeoutTask),
                            .persistTarget(deviceId: deviceId, target: nil),
                        ]
                    }

                    state = .shutterIsMovingToLocalTarget(
                        deviceId: deviceId,
                        position: position,
                        target: target,
                        timeoutTask: nil,
                        ignoresNextMatchingPosition: true
                    )
                    return [
                        .cancelTimeout(task: timeoutTask),
                        .startTimeout,
                    ]
                }

                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: nil
                )
                return [.cancelTimeout(task: timeoutTask)]

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
                    state = .shutterIsMovingToLocalTarget(
                        deviceId: deviceId,
                        position: oldPosition,
                        target: target,
                        timeoutTask: timeoutTask,
                        ignoresNextMatchingPosition: false
                    )
                    return []
                }

                if Self.hasReachedTarget(position: newPosition, target: target) {
                    state = .featureIsStarted(
                        deviceId: deviceId,
                        position: newPosition,
                        pendingLocalTarget: nil
                    )
                    return [
                        .cancelTimeout(task: timeoutTask),
                        .persistTarget(deviceId: deviceId, target: nil),
                    ]
                }

                state = .shutterIsMovingToLocalTarget(
                    deviceId: deviceId,
                    position: newPosition,
                    target: target,
                    timeoutTask: timeoutTask,
                    ignoresNextMatchingPosition: false
                )
                return []

            case let (.shutterIsMovingToLocalTarget(deviceId, position, _, timeoutTask, _), .timeoutHasExpired):
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: nil
                )
                return [
                    .cancelTimeout(task: timeoutTask),
                    .persistTarget(deviceId: deviceId, target: nil),
                ]

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
                state = .shutterIsMovingToLocalTarget(
                    deviceId: deviceId,
                    position: position,
                    target: target,
                    timeoutTask: timeoutTask,
                    ignoresNextMatchingPosition: ignoresNextMatchingPosition
                )
                return []

            default:
                return []
            }
        }

        private mutating func reducePositionWhileIdle(
            deviceId: DeviceIdentifier,
            position: Int,
            pendingLocalTarget: Int?
        ) -> [SingleShutterEffect] {
            guard let pendingLocalTarget else {
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: nil
                )
                return []
            }

            if Self.hasReachedTarget(position: position, target: pendingLocalTarget) {
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: nil
                )
                return [.persistTarget(deviceId: deviceId, target: nil)]
            }

            state = .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: position,
                target: pendingLocalTarget,
                timeoutTask: nil,
                ignoresNextMatchingPosition: true
            )
            return [.startTimeout]
        }

        private mutating func reducePositionWhileStarted(
            deviceId: DeviceIdentifier,
            position: Int,
            pendingLocalTarget: Int?
        ) -> [SingleShutterEffect] {
            guard let pendingLocalTarget else {
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: nil
                )
                return []
            }

            if Self.hasReachedTarget(position: position, target: pendingLocalTarget) {
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: nil
                )
                return [.persistTarget(deviceId: deviceId, target: nil)]
            }

            state = .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: position,
                target: pendingLocalTarget,
                timeoutTask: nil,
                ignoresNextMatchingPosition: true
            )
            return [.startTimeout]
        }

        private mutating func reduceObservedPendingLocalTarget(
            deviceId: DeviceIdentifier,
            position: Int,
            target: Int?
        ) -> [SingleShutterEffect] {
            guard let target else {
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: nil
                )
                return []
            }

            guard !Self.hasReachedTarget(position: position, target: target) else {
                state = .featureIsStarted(
                    deviceId: deviceId,
                    position: position,
                    pendingLocalTarget: nil
                )
                return [.persistTarget(deviceId: deviceId, target: nil)]
            }

            state = .shutterIsMovingToLocalTarget(
                deviceId: deviceId,
                position: position,
                target: target,
                timeoutTask: nil,
                ignoresNextMatchingPosition: true
            )
            return [.startTimeout]
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
        self.stateMachine = StateMachine(
            state: .featureIsIdle(
                deviceId: deviceId,
                position: 0,
                pendingLocalTarget: nil
            )
        )
        observationTask.task = Task { [weak self, worker] in
            await worker.observe(deviceId: deviceId) { [weak self] event in
                await self?.send(event)
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
        guard case .shutterIsMovingToLocalTarget = state else {
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
            onEvent: @escaping @Sendable (SingleShutterEvent) async -> Void
        ) async {
            let stream = await observeDeviceSource(deviceId)
            var previousSnapshot: (position: Int, pendingLocalTarget: Int?)?

            for await device in stream {
                guard !Task.isCancelled else { return }

                let snapshot = (
                    position: device?.shutterPosition ?? 0,
                    pendingLocalTarget: device?.shutterTargetPosition
                )

                if let previousSnapshot {
                    if previousSnapshot.pendingLocalTarget != snapshot.pendingLocalTarget {
                        await onEvent(.pendingLocalTargetWasObserved(target: snapshot.pendingLocalTarget))
                    }
                    if previousSnapshot.position != snapshot.position {
                        await onEvent(.positionWasReceived(position: snapshot.position))
                    }
                } else {
                    if snapshot.pendingLocalTarget != nil {
                        await onEvent(.pendingLocalTargetWasObserved(target: snapshot.pendingLocalTarget))
                    }
                    await onEvent(.positionWasReceived(position: snapshot.position))
                }

                previousSnapshot = snapshot
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
