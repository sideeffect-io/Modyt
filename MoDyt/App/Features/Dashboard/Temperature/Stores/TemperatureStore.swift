import Foundation
import Observation

@Observable
@MainActor
final class TemperatureStore: StartableStore {
    struct State: Sendable, Equatable {
        var descriptor: Descriptor?
    }

    enum Event: Sendable {
        case onAppear
        case descriptorWasResolved(Descriptor?)
    }

    enum Effect: Sendable, Equatable {
        case startObserving
    }

    struct StateMachine {
        static func reduce(
            _ state: State,
            _ event: Event
        ) -> Transition<State, Effect> {
            var state = state

            switch event {
            case .onAppear:
                return .init(state: state, effects: [.startObserving])

            case .descriptorWasResolved(let descriptor):
                if state.descriptor != descriptor {
                    state.descriptor = descriptor
                }
            }
            return .init(state: state)
        }
    }

    struct Descriptor: Sendable, Equatable {
        struct BatteryStatus: Sendable, Equatable {
            let defect: Bool?
            let level: Double?

            var normalizedLevel: Double? {
                guard let level else { return nil }
                return min(max(level, 0), 100)
            }
        }

        let value: Double
        let unitSymbol: String?
        let batteryStatus: BatteryStatus?
    }

    private(set) var state = State(descriptor: nil)

    var descriptor: Descriptor? {
        state.descriptor
    }

    private let observeTemperature: ObserveTemperatureEffectExecutor
    private var observationTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        observeTemperature: ObserveTemperatureEffectExecutor
    ) {
        self.observeTemperature = observeTemperature
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    isolated deinit {
        observationTask?.cancel()
    }

    func send(_ event: Event) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .startObserving:
                guard observationTask == nil else { return }
                replaceTask(
                    &observationTask,
                    with: makeTrackedStreamTask(
                        operation: { [observeTemperature] in
                            await observeTemperature()
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
        }
    }

    nonisolated static func observationEvent(from device: Device?) -> Event? {
        guard let device else {
            return .descriptorWasResolved(nil)
        }

        guard let descriptor = makeDescriptor(from: device) else {
            if isClimateCandidate(device) == false {
                return .descriptorWasResolved(nil)
            }
            return nil
        }

        return .descriptorWasResolved(descriptor)
    }

    nonisolated static func isClimateCandidate(_ device: Device) -> Bool {
        switch device.controlKind {
        case .temperature, .thermostat, .heatPump:
            return true
        default:
            return device.hasLikelyClimatePayload
        }
    }

    nonisolated static func makeDescriptor(from device: Device?) -> Descriptor? {
        guard let device else { return nil }
        guard isClimateCandidate(device) else {
            return nil
        }

        guard let signal = device.climateCurrentTemperatureSignal() else {
            return nil
        }

        return Descriptor(
            value: signal.value,
            unitSymbol: signal.unitSymbol,
            batteryStatus: batteryStatusDescriptor(data: device.data)
        )
    }

    private nonisolated static func batteryStatusDescriptor(data: [String: JSONValue]) -> Descriptor.BatteryStatus? {
        let batteryDefectSignal = firstSignalValue(
            keys: preferredBatteryDefectKeys,
            valueProvider: { key in normalizedBoolValue(forKey: key, data: data) }
        ) ?? firstLikelyBatteryDefectSignal(data: data)

        let batteryLevelSignal = firstSignalValue(
            keys: preferredBatteryLevelKeys,
            valueProvider: { key in numericValue(forKey: key, data: data) }
        ) ?? firstLikelyBatteryLevelSignal(data: data)

        guard batteryDefectSignal != nil || batteryLevelSignal != nil else {
            return nil
        }

        return Descriptor.BatteryStatus(
            defect: batteryDefectSignal?.value,
            level: batteryLevelSignal?.value
        )
    }

    private nonisolated static func firstLikelyBatteryDefectSignal(
        data: [String: JSONValue]
    ) -> (key: String, value: Bool)? {
        for key in data.keys.sorted() {
            guard isLikelyBatteryDefectKey(key) else { continue }
            guard let value = normalizedBoolValue(forKey: key, data: data) else { continue }
            return (key, value)
        }
        return nil
    }

    private nonisolated static func firstLikelyBatteryLevelSignal(
        data: [String: JSONValue]
    ) -> (key: String, value: Double)? {
        for key in data.keys.sorted() {
            guard isLikelyBatteryLevelKey(key) else { continue }
            guard let value = numericValue(forKey: key, data: data) else { continue }
            return (key, value)
        }
        return nil
    }

    private nonisolated static func numericValue(
        forKey key: String,
        data: [String: JSONValue]
    ) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }
        if let raw = data[key]?.stringValue {
            return Double(raw)
        }
        return nil
    }

    private nonisolated static func normalizedBoolValue(
        forKey key: String,
        data: [String: JSONValue]
    ) -> Bool? {
        if let value = data[key]?.boolValue {
            return value
        }
        if let number = data[key]?.numberValue {
            return number != 0
        }
        guard let raw = data[key]?.stringValue else { return nil }
        switch raw.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "1", "true", "on", "yes":
            return true
        case "0", "false", "off", "no":
            return false
        default:
            return nil
        }
    }

    private nonisolated static func firstSignalValue<Value>(
        keys: [String],
        valueProvider: (String) -> Value?
    ) -> (key: String, value: Value)? {
        for key in keys {
            guard let value = valueProvider(key) else { continue }
            return (key, value)
        }
        return nil
    }

    private nonisolated static func isLikelyBatteryDefectKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("batt") || normalized.contains("battery") else { return false }
        return normalized.contains("defect")
            || normalized.contains("fault")
            || normalized.contains("low")
    }

    private nonisolated static func isLikelyBatteryLevelKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("batt") || normalized.contains("battery") else { return false }
        if normalized.contains("defect") || normalized.contains("fault") || normalized.contains("low") {
            return false
        }
        return normalized.contains("level") || normalized == "battery"
    }

    private nonisolated static let preferredBatteryDefectKeys = [
        "battDefect",
        "batteryCmdDefect",
        "batteryDefect",
        "batteryLow",
        "battLow"
    ]

    private nonisolated static let preferredBatteryLevelKeys = [
        "battLevel",
        "batteryLevel",
        "battery"
    ]
}
