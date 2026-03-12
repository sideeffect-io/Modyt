import Foundation
import Observation

struct SingleLightPendingPresentation: Sendable, Equatable {
    let normalizedLevel: Double
    let isOn: Bool
    let normalizedColor: Double
}

struct SingleLightPendingCommand: Sendable, Equatable {
    let command: SingleLightGatewayCommand
    let presentation: SingleLightPendingPresentation
    let expectedPowerState: Bool?
    let expectedLevel: Int?
    let expectedColor: Int?

    func matches(_ descriptor: DrivingLightControlDescriptor?) -> Bool {
        guard let descriptor else { return false }

        if let expectedPowerState, descriptor.isOn != expectedPowerState {
            return false
        }

        if let expectedLevel,
           Int(descriptor.level.rounded()) != expectedLevel {
            return false
        }

        if let expectedColor,
           Int((descriptor.color?.value ?? Double.nan).rounded()) != expectedColor {
            return false
        }

        return true
    }
}

enum SingleLightState: Sendable, Equatable {
    case featureIsIdle(deviceId: DeviceIdentifier, descriptor: DrivingLightControlDescriptor?)
    case featureIsStarted(deviceId: DeviceIdentifier, descriptor: DrivingLightControlDescriptor?)
    case commandIsPending(
        deviceId: DeviceIdentifier,
        descriptor: DrivingLightControlDescriptor?,
        pendingCommand: SingleLightPendingCommand
    )

    var deviceId: DeviceIdentifier {
        switch self {
        case .featureIsIdle(let deviceId, _),
             .featureIsStarted(let deviceId, _),
             .commandIsPending(let deviceId, _, _):
            return deviceId
        }
    }

    var descriptor: DrivingLightControlDescriptor? {
        switch self {
        case .featureIsIdle(_, let descriptor),
             .featureIsStarted(_, let descriptor),
             .commandIsPending(_, let descriptor, _):
            return descriptor
        }
    }

    var pendingCommand: SingleLightPendingCommand? {
        guard case .commandIsPending(_, _, let pendingCommand) = self else { return nil }
        return pendingCommand
    }

    var displayedNormalizedLevel: Double {
        pendingCommand?.presentation.normalizedLevel
            ?? descriptor?.normalizedLevel
            ?? 0
    }

    var displayedIsOn: Bool {
        pendingCommand?.presentation.isOn
            ?? descriptor?.isOn
            ?? false
    }

    var displayedNormalizedColor: Double {
        pendingCommand?.presentation.normalizedColor
            ?? descriptor?.normalizedColor
            ?? DrivingLightControlDescriptor.defaultNormalizedColor
    }
}

enum SingleLightEvent: Sendable, Equatable {
    case descriptorWasReceived(DrivingLightControlDescriptor?)
    case levelWasCommitted(Double)
    case colorWasCommitted(Double)
    case powerWasSet(Bool)
}

enum SingleLightEffect: Sendable, Equatable {
    case sendCommand(SingleLightGatewayCommand)
}

@Observable
@MainActor
final class SingleLightStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: SingleLightState,
            _ event: SingleLightEvent
        ) -> Transition<SingleLightState, SingleLightEffect> {
            var state = state

            switch (state, event) {
            case let (.featureIsIdle(deviceId, _), .descriptorWasReceived(descriptor)):
                state = .featureIsStarted(deviceId: deviceId, descriptor: descriptor)
                return .init(state: state)

            case let (.featureIsStarted(deviceId, _), .descriptorWasReceived(descriptor)):
                state = .featureIsStarted(deviceId: deviceId, descriptor: descriptor)
                return .init(state: state)

            case let (.commandIsPending(deviceId, _, pendingCommand), .descriptorWasReceived(descriptor)):
                if pendingCommand.matches(descriptor) {
                    state = .featureIsStarted(deviceId: deviceId, descriptor: descriptor)
                } else {
                    state = .commandIsPending(
                        deviceId: deviceId,
                        descriptor: descriptor,
                        pendingCommand: pendingCommand
                    )
                }
                return .init(state: state)

            case let (.featureIsStarted(deviceId, descriptor), .levelWasCommitted(normalizedLevel)),
                 let (.commandIsPending(deviceId, descriptor, _), .levelWasCommitted(normalizedLevel)):
                let nextState = setLevel(
                    state: state,
                    deviceId: deviceId,
                    descriptor: descriptor,
                    normalizedLevel: normalizedLevel
                )
                return .init(
                    state: nextState,
                    effects: effect(for: nextState)
                )

            case let (.featureIsStarted(deviceId, descriptor), .powerWasSet(isOn)),
                 let (.commandIsPending(deviceId, descriptor, _), .powerWasSet(isOn)):
                let nextState = setPower(
                    state: state,
                    deviceId: deviceId,
                    descriptor: descriptor,
                    isOn: isOn
                )
                return .init(
                    state: nextState,
                    effects: effect(for: nextState)
                )

            case let (.featureIsStarted(deviceId, descriptor), .colorWasCommitted(normalizedColor)),
                 let (.commandIsPending(deviceId, descriptor, _), .colorWasCommitted(normalizedColor)):
                let nextState = setColor(
                    state: state,
                    deviceId: deviceId,
                    descriptor: descriptor,
                    normalizedColor: normalizedColor
                )
                return .init(
                    state: nextState,
                    effects: effect(for: nextState)
                )

            default:
                return .init(state: state)
            }
        }

        private static func effect(for state: SingleLightState) -> [SingleLightEffect] {
            guard case .commandIsPending(_, _, let pendingCommand) = state else {
                return []
            }
            return [.sendCommand(pendingCommand.command)]
        }

        private static func setLevel(
            state: SingleLightState,
            deviceId: DeviceIdentifier,
            descriptor: DrivingLightControlDescriptor?,
            normalizedLevel: Double
        ) -> SingleLightState {
            guard let descriptor,
                  let levelKey = descriptor.levelKey else { return state }

            let rawLevel = descriptor.rawLevel(forNormalizedLevel: normalizedLevel)
            let request = LightGatewayCommandRequest(
                deviceId: deviceId,
                signalName: levelKey,
                value: .int(rawLevel)
            )
            let command = SingleLightGatewayCommand.data(request)
            let pendingCommand = SingleLightPendingCommand(
                command: command,
                presentation: .init(
                    normalizedLevel: descriptor.normalizedLevel(forRawLevel: rawLevel),
                    isOn: descriptor.powerKey == nil ? descriptor.isLit(level: rawLevel) : descriptor.isOn,
                    normalizedColor: descriptor.normalizedColor
                ),
                expectedPowerState: nil,
                expectedLevel: rawLevel,
                expectedColor: nil
            )
            return .commandIsPending(
                deviceId: deviceId,
                descriptor: descriptor,
                pendingCommand: pendingCommand
            )
        }

        private static func setPower(
            state: SingleLightState,
            deviceId: DeviceIdentifier,
            descriptor: DrivingLightControlDescriptor?,
            isOn: Bool
        ) -> SingleLightState {
            guard let descriptor else { return state }

            if let powerKey = descriptor.powerKey {
                let request = LightGatewayCommandRequest(
                    deviceId: deviceId,
                    signalName: powerKey,
                    value: .bool(isOn)
                )
                let command = SingleLightGatewayCommand.data(request)
                let pendingCommand = SingleLightPendingCommand(
                    command: command,
                    presentation: .init(
                        normalizedLevel: descriptor.normalizedLevel,
                        isOn: isOn,
                        normalizedColor: descriptor.normalizedColor
                    ),
                    expectedPowerState: isOn,
                    expectedLevel: nil,
                    expectedColor: nil
                )
                return .commandIsPending(
                    deviceId: deviceId,
                    descriptor: descriptor,
                    pendingCommand: pendingCommand
                )
            }

            guard let levelKey = descriptor.levelKey else { return state }

            let rawLevel = isOn ? descriptor.maximumLevel : descriptor.minimumLevel
            let request = LightGatewayCommandRequest(
                deviceId: deviceId,
                signalName: levelKey,
                value: .int(rawLevel)
            )
            let command = SingleLightGatewayCommand.data(request)
            let pendingCommand = SingleLightPendingCommand(
                command: command,
                presentation: .init(
                    normalizedLevel: descriptor.normalizedLevel(forRawLevel: rawLevel),
                    isOn: isOn,
                    normalizedColor: descriptor.normalizedColor
                ),
                expectedPowerState: nil,
                expectedLevel: rawLevel,
                expectedColor: nil
            )
            return .commandIsPending(
                deviceId: deviceId,
                descriptor: descriptor,
                pendingCommand: pendingCommand
            )
        }

        private static func setColor(
            state: SingleLightState,
            deviceId: DeviceIdentifier,
            descriptor: DrivingLightControlDescriptor?,
            normalizedColor: Double
        ) -> SingleLightState {
            guard let descriptor,
                  let color = descriptor.color else { return state }

            let rawColor = color.rawValue(forNormalizedValue: normalizedColor)
            let command = SingleLightGatewayCommand.color(
                LightGatewayColorCommandRequest(
                    deviceId: deviceId,
                    signalName: color.key,
                    value: .int(rawColor),
                    colorModeSignalName: color.modeKey,
                    colorModeValue: color.modeValue
                )
            )
            let pendingCommand = SingleLightPendingCommand(
                command: command,
                presentation: .init(
                    normalizedLevel: descriptor.normalizedLevel,
                    isOn: descriptor.isOn,
                    normalizedColor: color.normalizedValue(forRawValue: rawColor)
                ),
                expectedPowerState: nil,
                expectedLevel: nil,
                expectedColor: rawColor
            )
            return .commandIsPending(
                deviceId: deviceId,
                descriptor: descriptor,
                pendingCommand: pendingCommand
            )
        }
    }

    private(set) var state: SingleLightState

    var descriptor: DrivingLightControlDescriptor? {
        state.descriptor
    }

    var displayedNormalizedLevel: Double {
        state.displayedNormalizedLevel
    }

    var displayedIsOn: Bool {
        state.displayedIsOn
    }

    var displayedNormalizedColor: Double {
        state.displayedNormalizedColor
    }

    var isInteractionEnabled: Bool {
        descriptor != nil
    }

    var isColorInteractionEnabled: Bool {
        descriptor?.color != nil
    }

    private let observeLight: ObserveSingleLightEffectExecutor
    private let sendCommand: SendSingleLightCommandEffectExecutor
    private var observationTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        deviceId: DeviceIdentifier,
        observeLight: ObserveSingleLightEffectExecutor,
        sendCommand: SendSingleLightCommandEffectExecutor
    ) {
        self.state = .featureIsIdle(deviceId: deviceId, descriptor: nil)
        self.observeLight = observeLight
        self.sendCommand = sendCommand
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        replaceTask(
            &observationTask,
            with: makeTrackedStreamTask(
                operation: { [observeLight] in
                    await observeLight()
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

    func send(_ event: SingleLightEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [SingleLightEffect]) {
        for effect in effects {
            switch effect {
            case .sendCommand(let command):
                launchFireAndForgetTask { [sendCommand] in
                    await sendCommand(command)
                }
            }
        }
    }
}
