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
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
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
            onDescriptor: @escaping @Sendable (Descriptor?) async -> Void
        ) async {
            let stream = await observeTemperature()
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onDescriptor(TemperatureStore.makeDescriptor(from: device))
            }
        }
    }

    private static func makeDescriptor(from device: Device?) -> Descriptor? {
        guard let device else { return nil }
        guard device.resolvedUsage == .thermo
            || device.resolvedUsage == .boiler
            || isLikelyThermostatPayload(device.data) else {
            return nil
        }

        for key in preferredTemperatureKeys {
            if let descriptor = temperatureDescriptor(forKey: key, device: device) {
                return descriptor
            }
        }

        for key in device.data.keys.sorted() {
            guard isLikelyTemperatureKey(key) else { continue }
            guard let descriptor = temperatureDescriptor(forKey: key, device: device) else { continue }
            if descriptor.unitSymbol != nil || key.localizedCaseInsensitiveContains("temperature") {
                return descriptor
            }
        }

        return nil
    }

    private static func isLikelyThermostatPayload(_ data: [String: JSONValue]) -> Bool {
        data.keys.contains { key in
            isLikelySetpointKey(key) || isLikelyHumidityKey(key)
        }
    }

    private static func temperatureDescriptor(forKey key: String, device: Device) -> Descriptor? {
        guard let value = numericValue(forKey: key, data: device.data) else { return nil }
        return Descriptor(
            value: value,
            unitSymbol: temperatureUnitSymbol(
                forKey: key,
                data: device.data,
                metadata: device.metadata
            ),
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

    private static func temperatureUnitSymbol(
        forKey key: String,
        data: [String: JSONValue],
        metadata: [String: JSONValue]?
    ) -> String? {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue,
            metadataObject?["unitLabel"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first {
            return normalizedTemperatureUnitSymbol(rawUnit)
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["temperatureUnit"]?.stringValue,
            data["tempUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first {
            return normalizedTemperatureUnitSymbol(rawUnit)
        }

        return nil
    }

    private static func normalizedTemperatureUnitSymbol(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        switch trimmed.lowercased() {
        case "na", "n/a", "none", "null", "-":
            return nil
        case "c", "°c", "celsius", "degc", "degcelsius":
            return "°C"
        case "f", "°f", "fahrenheit", "degf", "degfahrenheit":
            return "°F"
        case "k", "°k", "kelvin":
            return "K"
        default:
            return trimmed
        }
    }

    private static func isLikelyTemperatureKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.hasPrefix("config") { return false }
        if normalized == "lightpower" || normalized == "jobsmp" { return false }
        return normalized.contains("temp") || normalized.contains("temperature")
    }

    private static func isLikelySetpointKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.hasPrefix("min") || normalized.hasPrefix("max") {
            return false
        }
        return normalized.contains("setpoint")
    }

    private static func isLikelyHumidityKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("hygro") || normalized.contains("humidity")
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

    private static let preferredTemperatureKeys = [
        "outTemperature",
        "temperature",
        "ambientTemperature",
        "regTemperature",
        "devTemperature",
        "temp",
        "currentTemperature",
        "outdoorTemperature",
        "outsideTemperature",
        "measuredTemperature"
    ]

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
