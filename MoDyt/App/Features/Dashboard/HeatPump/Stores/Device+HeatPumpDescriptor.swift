import Foundation

extension Device {
    func heatPumpDescriptor() -> HeatPumpStore.Descriptor? {
        guard resolvedUsage == .thermo || resolvedUsage == .boiler || isLikelyHeatPumpPayload() else {
            return nil
        }

        let setpoint = heatPumpSetpoint()
        let temperature = heatPumpTemperature()

        guard setpoint != nil || temperature != nil else {
            return nil
        }

        return HeatPumpStore.Descriptor(
            temperature: temperature,
            setpointKey: setpoint?.key,
            setpoint: setpoint?.value,
            setpointRange: setpoint?.range ?? 5...30,
            setpointStep: setpoint?.step ?? 0.5,
            unitSymbol: setpoint?.unitSymbol ?? temperature?.unitSymbol
        )
    }

    private func isLikelyHeatPumpPayload() -> Bool {
        data.keys.contains { key in
            Self.isLikelySetpointKey(key) || Self.isLikelyTemperatureKey(key)
        }
    }

    private func heatPumpTemperature() -> HeatPumpStore.Descriptor.Temperature? {
        for key in Self.preferredTemperatureKeys {
            guard let descriptor = makeTemperature(forKey: key) else { continue }
            return descriptor
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyTemperatureKey(key) else { continue }
            guard let descriptor = makeTemperature(forKey: key) else { continue }
            return descriptor
        }

        return nil
    }

    private func makeTemperature(forKey key: String) -> HeatPumpStore.Descriptor.Temperature? {
        guard let value = numericHeatPumpValue(forKey: key) else { return nil }
        return HeatPumpStore.Descriptor.Temperature(
            value: value,
            unitSymbol: heatPumpTemperatureUnitSymbol(forKey: key)
        )
    }

    private struct SetpointValue {
        let key: String
        let value: Double
        let range: ClosedRange<Double>
        let step: Double
        let unitSymbol: String?
    }

    private func heatPumpSetpoint() -> SetpointValue? {
        for key in Self.preferredSetpointKeys {
            guard let value = numericHeatPumpValue(forKey: key) else { continue }
            return SetpointValue(
                key: key,
                value: value,
                range: setpointRange(forKey: key),
                step: setpointStep(forKey: key),
                unitSymbol: heatPumpTemperatureUnitSymbol(forKey: key)
            )
        }

        for key in data.keys.sorted() {
            guard Self.isLikelySetpointKey(key) else { continue }
            guard let value = numericHeatPumpValue(forKey: key) else { continue }
            return SetpointValue(
                key: key,
                value: value,
                range: setpointRange(forKey: key),
                step: setpointStep(forKey: key),
                unitSymbol: heatPumpTemperatureUnitSymbol(forKey: key)
            )
        }

        return nil
    }

    private func setpointRange(forKey key: String) -> ClosedRange<Double> {
        if let metadataRange = metadataRange(forKey: key) {
            return metadataRange
        }

        if let companionRange = companionSetpointRange(forKey: key) {
            return companionRange
        }

        return 5...30
    }

    private func companionSetpointRange(forKey key: String) -> ClosedRange<Double>? {
        let keys: (min: String, max: String)
        switch key {
        case "heatSetpoint":
            keys = ("minHeatSetpoint", "maxHeatSetpoint")
        case "coolSetpoint":
            keys = ("minCoolSetpoint", "maxCoolSetpoint")
        default:
            keys = ("minSetpoint", "maxSetpoint")
        }

        guard let minValue = numericHeatPumpValue(forKey: keys.min),
              let maxValue = numericHeatPumpValue(forKey: keys.max),
              minValue < maxValue else {
            return nil
        }

        return minValue...maxValue
    }

    private func setpointStep(forKey key: String) -> Double {
        if let metadataStep = metadata?[key]?.objectValue?["step"]?.numberValue,
           metadataStep > 0 {
            return metadataStep
        }
        return 0.5
    }

    private func numericHeatPumpValue(forKey key: String) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }
        if let raw = data[key]?.stringValue {
            return Double(raw)
        }
        return nil
    }

    private func metadataRange(forKey key: String) -> ClosedRange<Double>? {
        guard let object = metadata?[key]?.objectValue else { return nil }
        guard let minValue = object["min"]?.numberValue,
              let maxValue = object["max"]?.numberValue else { return nil }
        return minValue...maxValue
    }

    private func heatPumpTemperatureUnitSymbol(forKey key: String) -> String? {
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

    private func normalizedTemperatureUnitSymbol(_ raw: String) -> String? {
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

    private static let preferredTemperatureKeys = [
        "temperature",
        "ambientTemperature",
        "regTemperature",
        "devTemperature",
        "currentTemperature",
        "outTemperature",
        "temp",
        "outsideTemperature"
    ]

    private static let preferredSetpointKeys = [
        "setpoint",
        "currentSetpoint",
        "localSetpoint",
        "heatSetpoint",
        "coolSetpoint",
        "masterAbsSetpoint",
        "masterSchedSetpoint"
    ]
}
