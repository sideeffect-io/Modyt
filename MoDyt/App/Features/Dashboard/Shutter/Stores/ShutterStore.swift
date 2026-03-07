import Foundation
import Observation

enum ShutterPreset: Int, CaseIterable, Identifiable, Sendable {
    case open = 100
    case quarter = 75
    case half = 50
    case threeQuarter = 25
    case closed = 0

    var id: Int { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .open:
            return "Open"
        case .quarter:
            return "Quarter"
        case .half:
            return "Half"
        case .threeQuarter:
            return "Three quarters"
        case .closed:
            return "Closed"
        }
    }
}

enum ShutterMovementDirection: Sendable, Equatable {
    case idle
    case opening
    case closing
}

enum ShutterState: Sendable {
    private static let movementCompletionTolerance = 3

    case featureIsIdle(deviceIds: [DeviceIdentifier], position: Int, target: Int?)
    case featureIsStarted(deviceIds: [DeviceIdentifier], position: Int, target: Int?)
    case shutterIsMovingInApp(
        deviceIds: [DeviceIdentifier],
        position: Int,
        target: Int,
        timeoutTask: Task<Void, Never>? = nil,
        receivedValueCountAfterInAppTarget: Int? = nil
    )

    var deviceIds: [DeviceIdentifier] {
        switch self {
        case .featureIsIdle(let deviceIds, _, _),
             .featureIsStarted(let deviceIds, _, _),
             .shutterIsMovingInApp(let deviceIds, _, _, _, _):
            return deviceIds
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

    var movementDirection: ShutterMovementDirection {
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

extension ShutterState: Equatable {
    static func == (lhs: ShutterState, rhs: ShutterState) -> Bool {
        switch (lhs, rhs) {
        case let (
            .featureIsIdle(lhsDeviceIds, lhsPosition, lhsTarget),
            .featureIsIdle(rhsDeviceIds, rhsPosition, rhsTarget)
        ):
            return lhsDeviceIds == rhsDeviceIds
                && lhsPosition == rhsPosition
                && lhsTarget == rhsTarget

        case let (
            .featureIsStarted(lhsDeviceIds, lhsPosition, lhsTarget),
            .featureIsStarted(rhsDeviceIds, rhsPosition, rhsTarget)
        ):
            return lhsDeviceIds == rhsDeviceIds
                && lhsPosition == rhsPosition
                && lhsTarget == rhsTarget

        case let (
            .shutterIsMovingInApp(lhsDeviceIds, lhsPosition, lhsTarget, _, lhsReceivedValueCount),
            .shutterIsMovingInApp(rhsDeviceIds, rhsPosition, rhsTarget, _, rhsReceivedValueCount)
        ):
            return lhsDeviceIds == rhsDeviceIds
                && lhsPosition == rhsPosition
                && lhsTarget == rhsTarget
                && lhsReceivedValueCount == rhsReceivedValueCount

        default:
            return false
        }
    }
}

enum ShutterEvent: Sendable {
    case valueWasReceived(position: Int, target: Int?)
    case targetWasSetInApp(target: Int)
    case timeoutHasExpired
    case timeoutTaskWasCreated(task: Task<Void, Never>)
}

extension ShutterEvent: Equatable {
    static func == (lhs: ShutterEvent, rhs: ShutterEvent) -> Bool {
        switch (lhs, rhs) {
        case let (.valueWasReceived(lhsPosition, lhsTarget), .valueWasReceived(rhsPosition, rhsTarget)):
            return lhsPosition == rhsPosition && lhsTarget == rhsTarget

        case let (.targetWasSetInApp(lhsTarget), .targetWasSetInApp(rhsTarget)):
            return lhsTarget == rhsTarget

        case (.timeoutHasExpired, .timeoutHasExpired):
            return true

        case (.timeoutTaskWasCreated, .timeoutTaskWasCreated):
            // Task identity is intentionally ignored in event equality.
            return true

        default:
            return false
        }
    }
}

enum ShutterEffect: Sendable {
    case cancelTimeout(task: Task<Void, Never>?)
    case sendCommand(deviceIds: [DeviceIdentifier], position: Int)
    case startTimeout
    case persistTarget(deviceIds: [DeviceIdentifier], target: Int?)
}

extension ShutterEffect: Equatable {
    static func == (lhs: ShutterEffect, rhs: ShutterEffect) -> Bool {
        switch (lhs, rhs) {
        case (.cancelTimeout(task: _), .cancelTimeout(task: _)):
            // Task identity is intentionally ignored in effect equality.
            return true

        case let (
            .sendCommand(lhsDeviceIds, lhsPosition),
            .sendCommand(rhsDeviceIds, rhsPosition)
        ):
            return lhsDeviceIds == rhsDeviceIds && lhsPosition == rhsPosition

        case (.startTimeout, .startTimeout):
            return true

        case let (
            .persistTarget(lhsDeviceIds, lhsTarget),
            .persistTarget(rhsDeviceIds, rhsTarget)
        ):
            return lhsDeviceIds == rhsDeviceIds && lhsTarget == rhsTarget

        default:
            return false
        }
    }
}

@Observable
@MainActor
final class ShutterStore: StartableStore {
    struct StateMachine {
        private static let completionTolerance = 3

        var state: ShutterState = .featureIsIdle(
            deviceIds: [],
            position: 0,
            target: nil
        )

        mutating func reduce(_ event: ShutterEvent) -> [ShutterEffect] {
            print("--->>> SHUTTER REDUCER: current state=\(state), event=\(event)")
            switch (state, event) {
            case let (.featureIsIdle(deviceIds, _, _), .valueWasReceived(position, target)):
                state = .featureIsStarted(
                    deviceIds: deviceIds,
                    position: position,
                    target: target
                )
                return []

            case let (.featureIsStarted(deviceIds, oldPosition, oldTarget), .valueWasReceived(newPosition, newTarget)):
                if newTarget == nil, newPosition != oldPosition {
                    state = .featureIsStarted(
                        deviceIds: deviceIds,
                        position: newPosition,
                        target: nil
                    )
                    return []
                }

                if let newTarget, newTarget != oldTarget {
                    state = .shutterIsMovingInApp(
                        deviceIds: deviceIds,
                        position: newPosition,
                        target: newTarget,
                        timeoutTask: nil,
                        receivedValueCountAfterInAppTarget: nil
                    )
                    return [.startTimeout]
                }

                if newTarget == oldTarget, newPosition != oldPosition {
                    state = .featureIsStarted(
                        deviceIds: deviceIds,
                        position: newPosition,
                        target: newTarget
                    )
                    return []
                }

                return []

            case let (.featureIsStarted(deviceIds, position, _), .targetWasSetInApp(newTarget)):
                state = .shutterIsMovingInApp(
                    deviceIds: deviceIds,
                    position: position,
                    target: newTarget,
                    timeoutTask: nil,
                    receivedValueCountAfterInAppTarget: 0
                )
                return [
                    .sendCommand(deviceIds: deviceIds, position: newTarget),
                    .startTimeout,
                    .persistTarget(deviceIds: deviceIds, target: newTarget),
                ]

            case let (
                .shutterIsMovingInApp(deviceIds, position, oldTarget, timeoutTask, _),
                .targetWasSetInApp(newTarget)
            ) where newTarget != oldTarget:
                state = .shutterIsMovingInApp(
                    deviceIds: deviceIds,
                    position: position,
                    target: newTarget,
                    timeoutTask: nil,
                    receivedValueCountAfterInAppTarget: 0
                )
                return [
                    .cancelTimeout(task: timeoutTask),
                    .sendCommand(deviceIds: deviceIds, position: newTarget),
                    .startTimeout,
                    .persistTarget(deviceIds: deviceIds, target: newTarget),
                ]

            case let (
                .shutterIsMovingInApp(
                    deviceIds,
                    _,
                    oldTarget,
                    timeoutTask,
                    receivedValueCountAfterInAppTarget
                ),
                .valueWasReceived(newPosition, newTarget)
            ):
                let nextReceivedValueCount = receivedValueCountAfterInAppTarget.map { $0 + 1 }

                if let nextReceivedValueCount {
                    state = .shutterIsMovingInApp(
                        deviceIds: deviceIds,
                        position: newPosition,
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
                                deviceIds: deviceIds,
                                position: newPosition,
                                target: nil
                            )
                            return [
                                .cancelTimeout(task: timeoutTask),
                                .persistTarget(deviceIds: deviceIds, target: nil),
                            ]
                        }

                        state = .shutterIsMovingInApp(
                            deviceIds: deviceIds,
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
                        deviceIds: deviceIds,
                        position: newPosition,
                        target: nil
                    )
                    return [
                        .cancelTimeout(task: timeoutTask),
                        .persistTarget(deviceIds: deviceIds, target: nil),
                    ]
                }

                return []

            case let (.shutterIsMovingInApp(deviceIds, position, _, timeoutTask, _), .timeoutHasExpired):
                state = .featureIsStarted(
                    deviceIds: deviceIds,
                    position: position,
                    target: nil
                )
                return [
                    .cancelTimeout(task: timeoutTask),
                    .persistTarget(deviceIds: deviceIds, target: nil),
                ]

            case let (
                .shutterIsMovingInApp(
                    deviceIds,
                    position,
                    target,
                    _,
                    receivedValueCountAfterInAppTarget
                ),
                .timeoutTaskWasCreated(timeoutTask)
            ):
                state = .shutterIsMovingInApp(
                    deviceIds: deviceIds,
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
        let observeDevices: @Sendable ([DeviceIdentifier]) async -> any AsyncSequence<[Device], Never> & Sendable
        let sendCommand: @Sendable ([DeviceIdentifier], Int) async -> Void
        let sleep: @Sendable (Duration) async throws -> Void
        let persistTarget: @Sendable ([DeviceIdentifier], Int?) async -> Void

        init(
            observeDevices: @escaping @Sendable ([DeviceIdentifier]) async -> any AsyncSequence<[Device], Never> & Sendable,
            sendCommand: @escaping @Sendable ([DeviceIdentifier], Int) async -> Void,
            sleep: @escaping @Sendable (Duration) async throws -> Void,
            persistTarget: @escaping @Sendable ([DeviceIdentifier], Int?) async -> Void
        ) {
            self.observeDevices = observeDevices
            self.sendCommand = sendCommand
            self.sleep = sleep
            self.persistTarget = persistTarget
        }
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: ShutterState {
        stateMachine.state
    }

    private let deviceIds: [DeviceIdentifier]
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

    var movementDirection: ShutterMovementDirection {
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
        deviceIds: [DeviceIdentifier]
    ) {
        let orderedDeviceIds = deviceIds.uniquePreservingOrder()
        self.deviceIds = orderedDeviceIds
        self.dependencies = dependencies
        self.worker = Worker(
            observeDevices: dependencies.observeDevices,
            sendCommand: dependencies.sendCommand,
            persistTarget: dependencies.persistTarget
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let deviceIds = self.deviceIds
        self.stateMachine = StateMachine(state: .featureIsIdle(deviceIds: deviceIds, position: 0, target: nil))
        observationTask.task = Task { [weak self, worker] in
            await worker.observe(deviceIds: deviceIds) { [weak self] positions in
                await self?.send(
                    .valueWasReceived(
                        position: positions.position,
                        target: positions.target
                    )
                )
            }
        }
    }

    deinit {
        observationTask.cancel()
    }

    func send(_ event: ShutterEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    private func handle(_ effects: [ShutterEffect]) {
        for effect in effects {
            switch effect {
            case .cancelTimeout(let timeoutTask):
                timeoutTask?.cancel()

            case .sendCommand(let deviceIds, let position):
                Task { [worker] in
                    await worker.sendCommand(deviceIds: deviceIds, position: position)
                }

            case .startTimeout:
                startTimeoutIfNeeded()

            case .persistTarget(let deviceIds, let target):
                Task { [worker] in
                    await worker.persistTarget(deviceIds: deviceIds, target: target)
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
        private let observeDevicesSource: @Sendable ([DeviceIdentifier]) async -> any AsyncSequence<[Device], Never> & Sendable
        private let sendCommandAction: @Sendable ([DeviceIdentifier], Int) async -> Void
        private let persistTargetAction: @Sendable ([DeviceIdentifier], Int?) async -> Void

        init(
            observeDevices: @escaping @Sendable ([DeviceIdentifier]) async -> any AsyncSequence<[Device], Never> & Sendable,
            sendCommand: @escaping @Sendable ([DeviceIdentifier], Int) async -> Void,
            persistTarget: @escaping @Sendable ([DeviceIdentifier], Int?) async -> Void
        ) {
            self.observeDevicesSource = observeDevices
            self.sendCommandAction = sendCommand
            self.persistTargetAction = persistTarget
        }

        func observe(
            deviceIds: [DeviceIdentifier],
            onValues: @escaping @Sendable ((position: Int, target: Int?)) async -> Void
        ) async {
            let stream = await observeDevicesSource(deviceIds)
            var previousValues: (position: Int, target: Int?)?

            for await values in stream {
                guard !Task.isCancelled else { return }
                let averageValues = Self.averageValues(devices: values)

                if let previousValues {
                    guard previousValues.position != averageValues.position
                            || previousValues.target != averageValues.target else {
                        continue
                    }
                }

                await onValues(averageValues)
                previousValues = averageValues
            }
        }

        func sendCommand(deviceIds: [DeviceIdentifier], position: Int) async {
            await sendCommandAction(deviceIds, position)
        }

        func persistTarget(deviceIds: [DeviceIdentifier], target: Int?) async {
            await persistTargetAction(deviceIds, target)
        }

        private static func averageValues(devices: [Device]) -> (position: Int, target: Int?) {
            let positions = devices.compactMap(rawPosition(from:))
            let position = average(of: positions) ?? 0

            let targets = devices.compactMap(\.shutterTargetPosition)
            let target = average(of: targets)

            return (position, target)
        }

        private static func average(of values: [Int]) -> Int? {
            guard !values.isEmpty else { return nil }
            let sum = values.reduce(0, +)
            let average = Double(sum) / Double(values.count)
            return Int(average.rounded())
        }

        private static func rawPosition(from device: Device) -> Int? {
            device.shutterPosition
        }
    }
}
