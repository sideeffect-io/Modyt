import Foundation
import Observation

struct SingleLightControlContext: Sendable, Equatable {
    let deviceId: DeviceIdentifier
    let levelSignalName: String
    let rawLevelRange: ClosedRange<Double>
    let color: SingleLightColorContext?
}

struct SingleLightColorContext: Sendable, Equatable {
    let signalName: String
    let modeSignalName: String?
    let modeValue: String?
    let temperatureSignalName: String?
}

struct SingleLightValue: Sendable, Equatable {
    var normalizedLevel: Double
    var color: SingleLightColorValue?

    var isOn: Bool {
        normalizedLevel > 0.0001
    }
}

struct SingleLightColorValue: Sendable, Equatable {
    let preset: LightColorPreset
    let packedXY: Int
    let miredTemperatureW: Int?
}

struct SingleLightColorHold: Sendable {
    let timerTask: Task<Void, Never>?
    let lastObservedColor: SingleLightColorValue?
}

private func makeSingleLightColorValue(
    for preset: LightColorPreset
) -> SingleLightColorValue {
    SingleLightColorValue(
        preset: preset,
        packedXY: preset.packedXY,
        miredTemperatureW: preset.miredTemperatureW
    )
}

extension SingleLightColorHold: Equatable {
    static func == (lhs: SingleLightColorHold, rhs: SingleLightColorHold) -> Bool {
        lhs.lastObservedColor == rhs.lastObservedColor
    }
}

enum SingleLightState: Sendable {
    case idle(deviceId: DeviceIdentifier)
    case unavailable(deviceId: DeviceIdentifier)
    case ready(
        context: SingleLightControlContext,
        value: SingleLightValue,
        colorHold: SingleLightColorHold?
    )

    var deviceId: DeviceIdentifier {
        switch self {
        case .idle(let deviceId), .unavailable(let deviceId):
            return deviceId
        case .ready(let context, _, _):
            return context.deviceId
        }
    }

    var context: SingleLightControlContext? {
        guard case .ready(let context, _, _) = self else { return nil }
        return context
    }

    var value: SingleLightValue? {
        guard case .ready(_, let value, _) = self else { return nil }
        return value
    }

    var colorHold: SingleLightColorHold? {
        guard case .ready(_, _, let colorHold) = self else { return nil }
        return colorHold
    }
}

extension SingleLightState: Equatable {
    static func == (lhs: SingleLightState, rhs: SingleLightState) -> Bool {
        switch (lhs, rhs) {
        case let (.idle(lhsDeviceId), .idle(rhsDeviceId)):
            return lhsDeviceId == rhsDeviceId

        case let (.unavailable(lhsDeviceId), .unavailable(rhsDeviceId)):
            return lhsDeviceId == rhsDeviceId

        case let (
            .ready(lhsContext, lhsValue, lhsColorHold),
            .ready(rhsContext, rhsValue, rhsColorHold)
        ):
            return lhsContext == rhsContext
                && lhsValue == rhsValue
                && lhsColorHold == rhsColorHold

        default:
            return false
        }
    }
}

enum SingleLightEvent: Sendable {
    case started
    case gatewayDescriptorWasReceived(DrivingLightControlDescriptor?)
    case levelWasCommitted(Double)
    case powerWasToggled
    case presetWasSelected(LightColorPreset)
    case colorHoldTimerWasCreated(task: Task<Void, Never>)
    case colorHoldExpired
}

extension SingleLightEvent: Equatable {
    static func == (lhs: SingleLightEvent, rhs: SingleLightEvent) -> Bool {
        switch (lhs, rhs) {
        case (.started, .started):
            return true

        case let (
            .gatewayDescriptorWasReceived(lhsDescriptor),
            .gatewayDescriptorWasReceived(rhsDescriptor)
        ):
            return lhsDescriptor == rhsDescriptor

        case let (.levelWasCommitted(lhsLevel), .levelWasCommitted(rhsLevel)):
            return lhsLevel == rhsLevel

        case (.powerWasToggled, .powerWasToggled):
            return true

        case let (.presetWasSelected(lhsPreset), .presetWasSelected(rhsPreset)):
            return lhsPreset == rhsPreset

        case (.colorHoldTimerWasCreated, .colorHoldTimerWasCreated):
            return true

        case (.colorHoldExpired, .colorHoldExpired):
            return true

        default:
            return false
        }
    }
}

enum SingleLightEffect: Sendable {
    case observeGateway
    case sendLevel(LightGatewayCommandRequest)
    case sendColor(LightGatewayColorCommandRequest)
    case startColorHold
    case cancelColorHold(task: Task<Void, Never>?)
}

extension SingleLightEffect: Equatable {
    static func == (lhs: SingleLightEffect, rhs: SingleLightEffect) -> Bool {
        switch (lhs, rhs) {
        case (.observeGateway, .observeGateway):
            return true

        case let (.sendLevel(lhsRequest), .sendLevel(rhsRequest)):
            return lhsRequest == rhsRequest

        case let (.sendColor(lhsRequest), .sendColor(rhsRequest)):
            return lhsRequest == rhsRequest

        case (.startColorHold, .startColorHold):
            return true

        case (.cancelColorHold, .cancelColorHold):
            return true

        default:
            return false
        }
    }
}

@Observable
@MainActor
final class SingleLightStore: StartableStore {
    static let defaultColorHoldDuration: Duration = .seconds(60)

    struct StateMachine {
        static func reduce(
            _ state: SingleLightState,
            _ event: SingleLightEvent
        ) -> Transition<SingleLightState, SingleLightEffect> {
            switch event {
            case .started:
                return .init(state: state, effects: [.observeGateway])

            case .gatewayDescriptorWasReceived(let descriptor):
                return reduceGatewayDescriptorWasReceived(
                    from: state,
                    descriptor: descriptor
                )

            case .levelWasCommitted(let normalizedLevel):
                guard case .ready(let context, let value, let colorHold) = state else {
                    return .init(state: state)
                }

                let clampedNormalizedLevel = min(max(normalizedLevel, 0), 1)
                let rawLevel = rawLevel(
                    forNormalizedLevel: clampedNormalizedLevel,
                    in: context.rawLevelRange
                )
                let nextState = SingleLightState.ready(
                    context: context,
                    value: SingleLightValue(
                        normalizedLevel: normalizedLevelValue(
                            forRawLevel: rawLevel,
                            in: context.rawLevelRange
                        ),
                        color: value.color
                    ),
                    colorHold: colorHold
                )

                return .init(
                    state: nextState,
                    effects: [
                        .sendLevel(
                            LightGatewayCommandRequest(
                                deviceId: context.deviceId,
                                signalName: context.levelSignalName,
                                value: .int(rawLevel)
                            )
                        )
                    ]
                )

            case .powerWasToggled:
                guard case .ready(_, let value, _) = state else {
                    return .init(state: state)
                }

                return reduce(
                    state,
                    .levelWasCommitted(value.isOn ? 0 : 1)
                )

            case .presetWasSelected(let preset):
                guard case .ready(let context, var value, let colorHold) = state,
                      let colorContext = context.color else {
                    return .init(state: state)
                }

                let selectedColor = makeSingleLightColorValue(for: preset)
                value.color = selectedColor
                let nextColorHold = SingleLightColorHold(
                    timerTask: nil,
                    lastObservedColor: nil
                )

                return .init(
                    state: .ready(
                        context: context,
                        value: value,
                        colorHold: nextColorHold
                    ),
                    effects: [
                        .sendColor(
                            LightGatewayColorCommandRequest(
                                deviceId: context.deviceId,
                                signalName: colorContext.signalName,
                                value: .int(selectedColor.packedXY),
                                colorModeSignalName: colorContext.modeSignalName,
                                colorModeValue: colorContext.modeValue,
                                temperatureSignalName: nil,
                                temperatureValue: nil
                            )
                        ),
                        .cancelColorHold(task: colorHold?.timerTask),
                        .startColorHold,
                    ]
                )

            case .colorHoldTimerWasCreated(let task):
                guard case .ready(let context, let value, let colorHold?) = state else {
                    return .init(
                        state: state,
                        effects: [.cancelColorHold(task: task)]
                    )
                }

                let nextColorHold = SingleLightColorHold(
                    timerTask: task,
                    lastObservedColor: colorHold.lastObservedColor
                )

                return .init(
                    state: .ready(
                        context: context,
                        value: value,
                        colorHold: nextColorHold
                    )
                )

            case .colorHoldExpired:
                guard case .ready(let context, var value, let colorHold?) = state else {
                    return .init(state: state)
                }

                if let lastObservedColor = colorHold.lastObservedColor {
                    value.color = lastObservedColor
                }

                return .init(
                    state: .ready(
                        context: context,
                        value: value,
                        colorHold: nil
                    )
                )
            }
        }

        private static func reduceGatewayDescriptorWasReceived(
            from previousState: SingleLightState,
            descriptor: DrivingLightControlDescriptor?
        ) -> Transition<SingleLightState, SingleLightEffect> {
            let deviceId = previousState.deviceId

            guard let descriptor,
                  let levelSignalName = descriptor.levelKey else {
                let effects = previousState.colorHold.map {
                    [SingleLightEffect.cancelColorHold(task: $0.timerTask)]
                } ?? []
                return .init(
                    state: .unavailable(deviceId: deviceId),
                    effects: effects
                )
            }

            let previousContext = previousState.context
            let context = SingleLightControlContext(
                deviceId: deviceId,
                levelSignalName: levelSignalName,
                rawLevelRange: descriptor.range,
                color: descriptor.color.map(colorContext(from:))
                    ?? previousContext?.color
            )
            let observedColor = observedColorValue(from: descriptor.color)

            if case .ready(_, let previousValue, let colorHold?) = previousState {
                let nextColorHold = SingleLightColorHold(
                    timerTask: colorHold.timerTask,
                    lastObservedColor: observedColor ?? colorHold.lastObservedColor
                )
                let nextValue = SingleLightValue(
                    normalizedLevel: descriptor.normalizedLevel,
                    color: previousValue.color
                )

                return .init(
                    state: .ready(
                        context: context,
                        value: nextValue,
                        colorHold: nextColorHold
                    )
                )
            }

            let value = SingleLightValue(
                normalizedLevel: descriptor.normalizedLevel,
                color: observedColor ?? previousState.value?.color
            )

            return .init(
                state: .ready(
                    context: context,
                    value: value,
                    colorHold: nil
                )
            )
        }

        private static func colorContext(
            from descriptor: DrivingLightColorDescriptor
        ) -> SingleLightColorContext {
            SingleLightColorContext(
                signalName: descriptor.key,
                modeSignalName: descriptor.modeKey,
                modeValue: descriptor.modeValue,
                temperatureSignalName: descriptor.temperatureKey
            )
        }

        private static func observedColorValue(
            from descriptor: DrivingLightColorDescriptor?
        ) -> SingleLightColorValue? {
            guard let descriptor,
                  let preset = DrivingLightColorDescriptor.packedXYCalibration.nearestPreset(
                    forPackedXY: Int(descriptor.value.rounded())
                  ) else {
                return nil
            }

            return makeSingleLightColorValue(for: preset)
        }

        private static func rawLevel(
            forNormalizedLevel normalizedLevel: Double,
            in range: ClosedRange<Double>
        ) -> Int {
            let rawValue = range.lowerBound + ((range.upperBound - range.lowerBound) * normalizedLevel)
            return Int(rawValue.rounded())
        }

        private static func normalizedLevelValue(
            forRawLevel rawLevel: Int,
            in range: ClosedRange<Double>
        ) -> Double {
            let clampedLevel = min(max(Double(rawLevel), range.lowerBound), range.upperBound)
            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return 0 }
            return min(max((clampedLevel - range.lowerBound) / span, 0), 1)
        }
    }

    private(set) var state: SingleLightState

    var displayedNormalizedLevel: Double {
        state.value?.normalizedLevel ?? 0
    }

    var displayedIsOn: Bool {
        state.value?.isOn ?? false
    }

    var selectedPreset: LightColorPreset? {
        state.value?.color?.preset
    }

    var selectedPresetKind: LightColorPreset.Kind? {
        selectedPreset?.kind
    }

    var displayedNormalizedColor: Double {
        selectedPreset?.normalizedValue ?? DrivingLightControlDescriptor.defaultNormalizedColor
    }

    var isInteractionEnabled: Bool {
        state.context != nil
    }

    var isColorInteractionEnabled: Bool {
        state.context?.color != nil
    }

    private let observeLight: ObserveSingleLightEffectExecutor
    private let sendCommand: SendSingleLightCommandEffectExecutor
    private let colorHoldDuration: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var observationTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        deviceId: DeviceIdentifier,
        observeLight: ObserveSingleLightEffectExecutor,
        sendCommand: SendSingleLightCommandEffectExecutor,
        colorHoldDuration: Duration = SingleLightStore.defaultColorHoldDuration,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { duration in
            try await Task.sleep(for: duration)
        }
    ) {
        self.state = .idle(deviceId: deviceId)
        self.observeLight = observeLight
        self.sendCommand = sendCommand
        self.colorHoldDuration = colorHoldDuration
        self.sleep = sleep
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.started)
    }

    isolated deinit {
        observationTask?.cancel()
        state.colorHold?.timerTask?.cancel()
    }

    func send(_ event: SingleLightEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [SingleLightEffect]) {
        for effect in effects {
            switch effect {
            case .observeGateway:
                guard observationTask == nil else { continue }
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

            case .sendLevel(let request):
                launchFireAndForgetTask { [sendCommand] in
                    await sendCommand(.data(request))
                }

            case .sendColor(let request):
                launchFireAndForgetTask { [sendCommand] in
                    await sendCommand(.color(request))
                }

            case .startColorHold:
                startColorHoldIfNeeded()

            case .cancelColorHold(let task):
                task?.cancel()
            }
        }
    }

    private func startColorHoldIfNeeded() {
        guard case .ready(_, _, let colorHold?) = state,
              colorHold.timerTask == nil else {
            return
        }

        let holdTask = makeTrackedEventTask(
            operation: { [colorHoldDuration, sleep] in
                do {
                    try await sleep(colorHoldDuration)
                    return .colorHoldExpired
                } catch {
                    return nil
                }
            },
            onEvent: { [weak self] event in
                self?.send(event)
            }
        )

        send(.colorHoldTimerWasCreated(task: holdTask))
    }
}
