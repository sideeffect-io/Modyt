import Foundation

extension Device {
    func smokeStoreDescriptor() -> SmokeStore.Descriptor? {
        guard resolvedUsage == .smoke || resolvedUsage == .other else {
            return nil
        }

        let smokeSignal = firstSmokeSignalValue(
            keys: Self.preferredSmokeDefectKeys,
            valueProvider: smokeNormalizedBoolValue(forKey:)
        ) ?? firstLikelySmokeSignal()

        guard let smokeSignal else { return nil }

        return SmokeStore.Descriptor(
            smokeKey: smokeSignal.key,
            smokeDetected: smokeSignal.value,
            batteryStatus: smokeBatteryStatusDescriptor()
        )
    }

    private func smokeBatteryStatusDescriptor() -> SmokeStore.Descriptor.BatteryStatus? {
        let batteryDefectSignal = firstSmokeSignalValue(
            keys: Self.preferredSmokeBatteryDefectKeys,
            valueProvider: smokeNormalizedBoolValue(forKey:)
        ) ?? firstLikelySmokeBatteryDefectSignal()

        let batteryLevelSignal = firstSmokeSignalValue(
            keys: Self.preferredSmokeBatteryLevelKeys,
            valueProvider: smokeNumericValue(forKey:)
        ) ?? firstLikelySmokeBatteryLevelSignal()

        guard batteryDefectSignal != nil || batteryLevelSignal != nil else {
            return nil
        }

        return SmokeStore.Descriptor.BatteryStatus(
            batteryDefectKey: batteryDefectSignal?.key,
            batteryDefect: batteryDefectSignal?.value,
            batteryLevelKey: batteryLevelSignal?.key,
            batteryLevel: batteryLevelSignal?.value
        )
    }

    private func firstLikelySmokeSignal() -> (key: String, value: Bool)? {
        for key in data.keys.sorted() {
            guard Self.isLikelySmokeStateKey(key) else { continue }
            guard let value = smokeNormalizedBoolValue(forKey: key) else { continue }
            return (key, value)
        }
        return nil
    }

    private func firstLikelySmokeBatteryDefectSignal() -> (key: String, value: Bool)? {
        for key in data.keys.sorted() {
            guard Self.isLikelySmokeBatteryDefectKey(key) else { continue }
            guard let value = smokeNormalizedBoolValue(forKey: key) else { continue }
            return (key, value)
        }
        return nil
    }

    private func firstLikelySmokeBatteryLevelSignal() -> (key: String, value: Double)? {
        for key in data.keys.sorted() {
            guard Self.isLikelySmokeBatteryLevelKey(key) else { continue }
            guard let value = smokeNumericValue(forKey: key) else { continue }
            return (key, value)
        }
        return nil
    }

    private func smokeNumericValue(forKey key: String) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }
        if let raw = data[key]?.stringValue {
            return Double(raw)
        }
        return nil
    }

    private func smokeNormalizedBoolValue(forKey key: String) -> Bool? {
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

    private func firstSmokeSignalValue<Value>(
        keys: [String],
        valueProvider: (String) -> Value?
    ) -> (key: String, value: Value)? {
        for key in keys {
            guard let value = valueProvider(key) else { continue }
            return (key, value)
        }
        return nil
    }

    private static func isLikelySmokeStateKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("smoke") || normalized.contains("fire") else { return false }
        return normalized.contains("defect")
            || normalized.contains("alarm")
            || normalized.contains("detect")
            || normalized.hasSuffix("state")
    }

    private static func isLikelySmokeBatteryDefectKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("batt") || normalized.contains("battery") else { return false }
        return normalized.contains("defect")
            || normalized.contains("fault")
            || normalized.contains("low")
    }

    private static func isLikelySmokeBatteryLevelKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("batt") || normalized.contains("battery") else { return false }
        if normalized.contains("defect") || normalized.contains("fault") || normalized.contains("low") {
            return false
        }
        return normalized.contains("level") || normalized == "battery"
    }

    private static let preferredSmokeDefectKeys = [
        "techSmokeDefect",
        "smokeDefect",
        "smokeDetected",
        "smokeAlarm",
        "fireAlarm"
    ]

    private static let preferredSmokeBatteryDefectKeys = [
        "battDefect",
        "batteryCmdDefect",
        "batteryDefect",
        "batteryLow",
        "battLow"
    ]

    private static let preferredSmokeBatteryLevelKeys = [
        "battLevel",
        "batteryLevel",
        "battery"
    ]
}
