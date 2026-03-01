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

enum ShutterState: Sendable, Equatable {
    case featureIsIdle(deviceIds: [DeviceIdentifier], position: Int, target: Int?)
    case featureIsStarted(deviceIds: [DeviceIdentifier], position: Int, target: Int?)
    case shutterIsMovingInApp(deviceIds: [DeviceIdentifier], position: Int, target: Int, hasTargetBeenACKed: Bool = false)

    var deviceIds: [DeviceIdentifier] {
        switch self {
        case .featureIsIdle(let deviceIds, _, _),
             .featureIsStarted(let deviceIds, _, _),
             .shutterIsMovingInApp(let deviceIds, _, _, _):
            return deviceIds
        }
    }

    var position: Int {
        switch self {
        case .featureIsIdle(_, let position, _),
             .featureIsStarted(_, let position, _),
             .shutterIsMovingInApp(_, let position, _, _):
            return position
        }
    }

    var gaugePosition: Int {
        ShutterPositionMapper.gaugePosition(from: position)
    }

    var target: Int? {
        switch self {
        case .featureIsIdle(_, _, let target),
             .featureIsStarted(_, _, let target):
            return target
        case .shutterIsMovingInApp(_, _, let target, _):
            return target
        }
    }

    var movingTarget: Int? {
        if case .shutterIsMovingInApp(_, _, let target, _) = self {
            return target
        }
        return nil
    }
}

enum ShutterEvent: Sendable, Equatable {
    case valueWasReceived(position: Int, target: Int?)
    case targetWasSetInApp(target: Int)
    case timeoutHasExpired
}

enum ShutterEffect: Sendable, Equatable {
    case sendCommand(deviceIds: [DeviceIdentifier], position: Int)
    case startTimeout
    case setTarget(deviceIds: [DeviceIdentifier], target: Int?)
}

enum ShutterReducer {
    static func reduce(
        state: ShutterState,
        event: ShutterEvent
    ) -> (ShutterState, [ShutterEffect]) {
        print("--->>> new event received: state=\(state), event=\(event)")
        switch (state, event) {
        case let (.featureIsIdle(deviceIds, _, _), .valueWasReceived(position, target)):
            return (
                .featureIsStarted(
                    deviceIds: deviceIds,
                    position: position,
                    target: target
                ),
                []
            )

        case let (.featureIsStarted(deviceIds, oldPosition, oldTarget), .valueWasReceived(nextPosition, nextTarget)):
            
            guard oldPosition != nextPosition && oldTarget != nextTarget else {
                return (.featureIsStarted(deviceIds: deviceIds, position: oldPosition, target: oldTarget), [])
            }
            
            guard let nextTarget else {
                return (
                    .featureIsStarted(
                        deviceIds: deviceIds,
                        position: nextPosition,
                        target: nil
                    ),
                    []
                )
            }

            return (
                .shutterIsMovingInApp(
                    deviceIds: deviceIds,
                    position: nextPosition,
                    target: nextTarget
                ),
                [
                    .startTimeout
                ]
            )

        case let (.featureIsStarted(deviceIds, position, _), .targetWasSetInApp(target)):
            let nextTarget = target
            return (
                .shutterIsMovingInApp(
                    deviceIds: deviceIds,
                    position: position,
                    target: nextTarget
                ),
                [
                    .sendCommand(deviceIds: deviceIds, position: nextTarget),
                    .startTimeout,
                    .setTarget(deviceIds: deviceIds, target: nextTarget),
                ]
            )

        case let (
            .shutterIsMovingInApp(deviceIds, oldPosition, oldTarget, hasTargetBeenACKed),
            .valueWasReceived(newPosition, newTarget)
        ):
            
            if !hasTargetBeenACKed, newPosition == oldTarget {
                // frame is probably an ack for the target
                return
                    (
                        .shutterIsMovingInApp(
                            deviceIds: deviceIds,
                            position: oldPosition,
                            target: oldTarget,
                            hasTargetBeenACKed: true),
                        []
                    )
            }
            
            if newTarget == oldTarget, newPosition.isAlmostEqual(to: oldTarget) {
                return (
                    .featureIsStarted(
                        deviceIds: deviceIds,
                        position: newPosition,
                        target: nil
                    ),
                    [.setTarget(deviceIds: deviceIds, target: nil)]
                )
            }
            
            if newTarget != oldTarget {
                if let newTarget {
                    return (
                        .shutterIsMovingInApp(
                            deviceIds: deviceIds,
                            position: newPosition,
                            target: newTarget,
                            hasTargetBeenACKed: hasTargetBeenACKed
                        ),
                        [.startTimeout]
                    )
                }
            }

            return (
                .shutterIsMovingInApp(
                    deviceIds: deviceIds,
                    position: newPosition,
                    target: oldTarget,
                    hasTargetBeenACKed: hasTargetBeenACKed
                ),
                []
            )

        case let (.shutterIsMovingInApp(deviceIds, position, _, _), .timeoutHasExpired):
            return (
                .featureIsStarted(
                    deviceIds: deviceIds,
                    position: position,
                    target: nil
                ),
                [.setTarget(deviceIds: deviceIds, target: nil)]
            )

        default:
            return (state, [])
        }
    }
}

@Observable
@MainActor
final class ShutterStore {
    struct Dependencies {
        let observeDevices: @Sendable ([DeviceIdentifier]) async -> any AsyncSequence<[Device], Never> & Sendable
        let sendCommand: @Sendable ([DeviceIdentifier], Int) async -> Void
        let sleep: @Sendable () async throws -> Void
        let setTarget: @Sendable ([DeviceIdentifier], Int?) async -> Void

        init(
            observeDevices: @escaping @Sendable ([DeviceIdentifier]) async -> any AsyncSequence<[Device], Never> & Sendable,
            sendCommand: @escaping @Sendable ([DeviceIdentifier], Int) async -> Void,
            sleep: @escaping @Sendable () async throws -> Void,
            setTarget: @escaping @Sendable ([DeviceIdentifier], Int?) async -> Void
        ) {
            self.observeDevices = observeDevices
            self.sendCommand = sendCommand
            self.sleep = sleep
            self.setTarget = setTarget
        }
    }

    private(set) var state: ShutterState

    private let dependencies: Dependencies
    private let observationTask = TaskHandle()
    private var timeoutTask: Task<Void, Never>?
    private let worker: Worker

    var position: Int {
        state.position
    }

    var gaugePosition: Int {
        state.gaugePosition
    }

    var target: Int? {
        state.target
    }

    var movingTarget: Int? {
        state.movingTarget
    }

    init(
        deviceIds: [DeviceIdentifier],
        dependencies: Dependencies
    ) {
        let orderedDeviceIds = deviceIds.uniquePreservingOrder()
        self.state = .featureIsIdle(
            deviceIds: orderedDeviceIds,
            position: 0,
            target: nil
        )
        self.dependencies = dependencies
        self.worker = Worker(
            observeDevices: dependencies.observeDevices,
            sendCommand: dependencies.sendCommand,
            setTarget: dependencies.setTarget
        )

        observationTask.task = Task { [weak self, worker, orderedDeviceIds] in
            await worker.observe(deviceIds: orderedDeviceIds) { [weak self] positions in
                await self?.handleIncomingDevices(positions)
            }
        }
    }

    func send(_ event: ShutterEvent) {
        let previousState = state
        let (nextState, effects) = ShutterReducer.reduce(state: state, event: event)
        state = nextState

        if Self.isMoving(previousState) && Self.isMoving(nextState) == false {
            timeoutTask?.cancel()
            timeoutTask = nil
        }

        handle(effects)
    }

    private func handleIncomingDevices(_ positions: (position: Int, target: Int?)) {
        send(
            .valueWasReceived(
                position: positions.position,
                target: positions.target
            )
        )
    }

    private func handle(_ effects: [ShutterEffect]) {
        print("--->>> new effects received: effects=\(effects)")

        for effect in effects {
            switch effect {
            case .sendCommand(let deviceIds, let position):
                Task { [worker] in
                    await worker.sendCommand(deviceIds: deviceIds, position: position)
                }
            case .startTimeout:
                timeoutTask?.cancel()
                timeoutTask = Task { [weak self] in
                    do {
                        try await self?.dependencies.sleep()
                        self?.send(.timeoutHasExpired)
                    } catch {
                        
                    }
                }
            case .setTarget(let deviceIds, let target):
                timeoutTask?.cancel()
                Task { [worker] in
                    await worker.setTarget(deviceIds: deviceIds, target: target)
                }
            }
        }
    }

    private actor Worker {
        private let observeDevicesSource: @Sendable ([DeviceIdentifier]) async -> any AsyncSequence<[Device], Never>
        private let sendCommandAction: @Sendable ([DeviceIdentifier], Int) async -> Void
        private let setTargetAction: @Sendable ([DeviceIdentifier], Int?) async -> Void

        init(
            observeDevices: @escaping @Sendable ([DeviceIdentifier]) async -> any AsyncSequence<[Device], Never>,
            sendCommand: @escaping @Sendable ([DeviceIdentifier], Int) async -> Void,
            setTarget: @escaping @Sendable ([DeviceIdentifier], Int?) async -> Void
        ) {
            self.observeDevicesSource = observeDevices
            self.sendCommandAction = sendCommand
            self.setTargetAction = setTarget
        }

        func observe(
            deviceIds: [DeviceIdentifier],
            onValues: @escaping @Sendable ((position: Int, target: Int?)) async -> Void
        ) async {
            let stream = await observeDevicesSource(deviceIds)
            
            var previousValues: (position: Int, target: Int?)? = nil
            
            for await values in stream {
                guard !Task.isCancelled else { return }
                let averageValues = Self.averageValues(devices: values)
                if let truePreviousValues = previousValues {
                    if truePreviousValues.position != averageValues.position || truePreviousValues.target != averageValues.target {
                        await onValues(averageValues)
                    }
                    previousValues = averageValues
                } else {
                    await onValues(averageValues)
                    previousValues = averageValues
                }
            }
        }

        func sendCommand(deviceIds: [DeviceIdentifier], position: Int) async {
            await sendCommandAction(deviceIds, position)
        }

        func setTarget(deviceIds: [DeviceIdentifier], target: Int?) async {
            await setTargetAction(deviceIds, target)
        }
        
        private static func averageValues(devices: [Device]) -> (position: Int, target: Int?) {
            let positions = devices.compactMap(rawPosition(from:))
            let position = average(of: positions) ?? 0

            let targets = devices.compactMap(\.shutterTargetPosition)
            let target = average(of: targets)

            return (position, target)
        }
        
        private static func average(of values: [Int]) -> Int? {
            guard values.isEmpty == false else { return nil }
            let sum = values.reduce(0, +)
            let average = Double(sum) / Double(values.count)
            return Int(average.rounded())
        }
        
        private static func rawPosition(from device: Device) -> Int? {
            device.shutterPosition
        }
    }

    private static func isMoving(_ state: ShutterState) -> Bool {
        if case .shutterIsMovingInApp = state {
            return true
        }
        return false
    }
}

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    deinit {
        task?.cancel()
    }
}
