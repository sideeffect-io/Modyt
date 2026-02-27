import Foundation
import Observation

@Observable
@MainActor
final class TemperatureStore {
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

    struct Dependencies {
        let observeTemperature: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeTemperature: @escaping @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeTemperature = observeTemperature
        }
    }

    private(set) var descriptor: Descriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(dependencies: Dependencies) {
        self.descriptor = nil
        self.worker = Worker(observeTemperature: dependencies.observeTemperature)

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] device, descriptor in
                await self?.applyIncomingObservation(device: device, descriptor: descriptor)
            }
        }
    }

    private func applyIncomingObservation(device: Device?, descriptor: Descriptor?) {
        guard let device else {
            applyIncomingDescriptor(nil)
            return
        }

        guard let descriptor else {
            if Self.isClimateCandidate(device) == false {
                applyIncomingDescriptor(nil)
            }
            return
        }

        applyIncomingDescriptor(descriptor)
    }

    private func applyIncomingDescriptor(_ descriptor: Descriptor?) {
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private actor Worker {
        private let observeTemperature: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeTemperature: @escaping @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeTemperature = observeTemperature
        }

        func observe(
            onObservation: @escaping @Sendable (Device?, Descriptor?) async -> Void
        ) async {
            let stream = await observeTemperature()
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onObservation(device, TemperatureStore.makeDescriptor(from: device))
            }
        }
    }

    private static func isClimateCandidate(_ device: Device) -> Bool {
        switch device.controlKind {
        case .temperature, .thermostat, .heatPump:
            return true
        default:
            return device.hasLikelyClimatePayload
        }
    }

    private static func makeDescriptor(from device: Device?) -> Descriptor? {
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

    private static func batteryStatusDescriptor(data: [String: JSONValue]) -> Descriptor.BatteryStatus? {
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

    private static func firstLikelyBatteryDefectSignal(
        data: [String: JSONValue]
    ) -> (key: String, value: Bool)? {
        for key in data.keys.sorted() {
            guard isLikelyBatteryDefectKey(key) else { continue }
            guard let value = normalizedBoolValue(forKey: key, data: data) else { continue }
            return (key, value)
        }
        return nil
    }

    private static func firstLikelyBatteryLevelSignal(
        data: [String: JSONValue]
    ) -> (key: String, value: Double)? {
        for key in data.keys.sorted() {
            guard isLikelyBatteryLevelKey(key) else { continue }
            guard let value = numericValue(forKey: key, data: data) else { continue }
            return (key, value)
        }
        return nil
    }

    private static func numericValue(
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

    private static func normalizedBoolValue(
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

    private static func firstSignalValue<Value>(
        keys: [String],
        valueProvider: (String) -> Value?
    ) -> (key: String, value: Value)? {
        for key in keys {
            guard let value = valueProvider(key) else { continue }
            return (key, value)
        }
        return nil
    }

    private static func isLikelyBatteryDefectKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("batt") || normalized.contains("battery") else { return false }
        return normalized.contains("defect")
            || normalized.contains("fault")
            || normalized.contains("low")
    }

    private static func isLikelyBatteryLevelKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("batt") || normalized.contains("battery") else { return false }
        if normalized.contains("defect") || normalized.contains("fault") || normalized.contains("low") {
            return false
        }
        return normalized.contains("level") || normalized == "battery"
    }

    private static let preferredBatteryDefectKeys = [
        "battDefect",
        "batteryCmdDefect",
        "batteryDefect",
        "batteryLow",
        "battLow"
    ]

    private static let preferredBatteryLevelKeys = [
        "battLevel",
        "batteryLevel",
        "battery"
    ]
}

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    deinit {
        task?.cancel()
    }
}
