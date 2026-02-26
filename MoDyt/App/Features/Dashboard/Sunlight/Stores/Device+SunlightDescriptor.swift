import Foundation

extension Device {
    func sunlightStoreDescriptor() -> SunlightStore.Descriptor? {
        guard resolvedUsage == .weather || resolvedUsage == .other else {
            return nil
        }

        for key in Self.preferredSunlightKeys {
            if let descriptor = makeSunlightStoreDescriptor(forKey: key) {
                return descriptor
            }
        }

        for key in data.keys.sorted() {
            guard Self.isLikelySunlightKey(key) else { continue }
            guard let descriptor = makeSunlightStoreDescriptor(forKey: key) else { continue }
            return descriptor
        }

        return nil
    }

    private func makeSunlightStoreDescriptor(forKey key: String) -> SunlightStore.Descriptor? {
        guard let rawValue = sunlightNumericValue(forKey: key) else {
            return nil
        }

        let unit = sunlightUnit(forKey: key)
        return SunlightStore.Descriptor(
            key: key,
            value: rawValue * unit.multiplier,
            range: Self.defaultSunlightRange,
            unitSymbol: unit.symbol,
            batteryStatus: sunlightBatteryStatusDescriptor()
        )
    }

    private func sunlightBatteryStatusDescriptor() -> SunlightStore.Descriptor.BatteryStatus? {
        let batteryDefectSignal = firstSunlightSignalValue(
            keys: Self.preferredSunlightBatteryDefectKeys,
            valueProvider: sunlightNormalizedBoolValue(forKey:)
        ) ?? firstLikelySunlightBatteryDefectSignal()

        let batteryLevelSignal = firstSunlightSignalValue(
            keys: Self.preferredSunlightBatteryLevelKeys,
            valueProvider: sunlightNumericValue(forKey:)
        ) ?? firstLikelySunlightBatteryLevelSignal()

        guard batteryDefectSignal != nil || batteryLevelSignal != nil else {
            return nil
        }

        return SunlightStore.Descriptor.BatteryStatus(
            batteryDefectKey: batteryDefectSignal?.key,
            batteryDefect: batteryDefectSignal?.value,
            batteryLevelKey: batteryLevelSignal?.key,
            batteryLevel: batteryLevelSignal?.value
        )
    }

    private func firstLikelySunlightBatteryDefectSignal() -> (key: String, value: Bool)? {
        for key in data.keys.sorted() {
            guard Self.isLikelySunlightBatteryDefectKey(key) else { continue }
            guard let value = sunlightNormalizedBoolValue(forKey: key) else { continue }
            return (key, value)
        }
        return nil
    }

    private func firstLikelySunlightBatteryLevelSignal() -> (key: String, value: Double)? {
        for key in data.keys.sorted() {
            guard Self.isLikelySunlightBatteryLevelKey(key) else { continue }
            guard let value = sunlightNumericValue(forKey: key) else { continue }
            return (key, value)
        }
        return nil
    }

    private func sunlightNumericValue(forKey key: String) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }
        if let raw = data[key]?.stringValue {
            return Double(raw)
        }
        return nil
    }

    private func sunlightNormalizedBoolValue(forKey key: String) -> Bool? {
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

    private func firstSunlightSignalValue<Value>(
        keys: [String],
        valueProvider: (String) -> Value?
    ) -> (key: String, value: Value)? {
        for key in keys {
            guard let value = valueProvider(key) else { continue }
            return (key, value)
        }
        return nil
    }

    private struct SunlightUnit {
        let symbol: String
        let multiplier: Double
    }

    private func sunlightUnit(forKey key: String) -> SunlightUnit {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first,
           let unit = normalizedSunlightUnit(rawUnit) {
            return unit
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["sunlightUnit"]?.stringValue,
            data["irradianceUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first,
           let unit = normalizedSunlightUnit(rawUnit) {
            return unit
        }

        return SunlightUnit(symbol: "W/m2", multiplier: 1)
    }

    private func normalizedSunlightUnit(_ raw: String) -> SunlightUnit? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return nil
        }

        let canonical = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "^", with: "")
            .replacingOccurrences(of: "²", with: "2")

        switch canonical {
        case "na", "n/a", "none", "null", "-":
            return nil
        case "w/m2", "wm2", "watt/m2", "wattperm2":
            return SunlightUnit(symbol: "W/m2", multiplier: 1)
        case "kw/m2", "kwm2", "kilowatt/m2", "kilowattperm2":
            return SunlightUnit(symbol: "W/m2", multiplier: 1000)
        default:
            return SunlightUnit(symbol: trimmed, multiplier: 1)
        }
    }

    private static func isLikelySunlightKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized == "lightpower"
            || normalized.contains("sun")
            || normalized.contains("solar")
            || normalized.contains("irradiance")
            || normalized.contains("radiation")
    }

    private static func isLikelySunlightBatteryDefectKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("batt") || normalized.contains("battery") else { return false }
        return normalized.contains("defect")
            || normalized.contains("fault")
            || normalized.contains("low")
    }

    private static func isLikelySunlightBatteryLevelKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        guard normalized.contains("batt") || normalized.contains("battery") else { return false }
        if normalized.contains("defect") || normalized.contains("fault") || normalized.contains("low") {
            return false
        }
        return normalized.contains("level") || normalized == "battery"
    }

    private static let preferredSunlightKeys = [
        "lightPower",
        "sunlightPower",
        "sunlight",
        "solarRadiation",
        "solarIrradiance",
        "irradiance",
        "globalRadiation"
    ]

    private static let preferredSunlightBatteryDefectKeys = [
        "battDefect",
        "batteryCmdDefect",
        "batteryDefect",
        "batteryLow",
        "battLow"
    ]

    private static let preferredSunlightBatteryLevelKeys = [
        "battLevel",
        "batteryLevel",
        "battery"
    ]

    private static let defaultSunlightRange: ClosedRange<Double> = 0...1400
}
