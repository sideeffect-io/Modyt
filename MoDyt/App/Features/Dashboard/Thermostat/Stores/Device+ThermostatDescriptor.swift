import Foundation

extension Device {
    func thermostatDescriptor() -> ThermostatStore.Descriptor? {
        guard resolvedUsage == .boiler || resolvedUsage == .thermo || thermostatHasLikelyPayload else {
            return nil
        }

        let temperature = thermostatTemperatureDescriptor()
        let humidity = thermostatHumidityDescriptor()

        guard temperature != nil || humidity != nil else { return nil }
        return ThermostatStore.Descriptor(
            temperature: temperature,
            humidity: humidity
        )
    }

    private var thermostatHasLikelyPayload: Bool {
        data.keys.contains { key in
            Self.isLikelyThermostatSetpointKey(key) || Self.isLikelyThermostatHumidityKey(key)
        }
    }

    private func thermostatTemperatureDescriptor() -> ThermostatStore.Descriptor.Temperature? {
        for key in Self.preferredThermostatTemperatureKeys {
            if let descriptor = thermostatTemperatureDescriptor(forKey: key) {
                return descriptor
            }
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyThermostatTemperatureKey(key) else { continue }
            guard let descriptor = thermostatTemperatureDescriptor(forKey: key) else { continue }
            if descriptor.unitSymbol != nil || key.localizedCaseInsensitiveContains("temperature") {
                return descriptor
            }
        }

        return nil
    }

    private func thermostatHumidityDescriptor() -> ThermostatStore.Descriptor.Humidity? {
        for key in Self.preferredThermostatHumidityKeys {
            guard let value = thermostatNumericValue(forKey: key) else { continue }
            return ThermostatStore.Descriptor.Humidity(
                value: value,
                unitSymbol: thermostatHumidityUnitSymbol(forKey: key) ?? "%"
            )
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyThermostatHumidityKey(key) else { continue }
            guard let value = thermostatNumericValue(forKey: key) else { continue }
            return ThermostatStore.Descriptor.Humidity(
                value: value,
                unitSymbol: thermostatHumidityUnitSymbol(forKey: key) ?? "%"
            )
        }

        return nil
    }

    private func thermostatTemperatureDescriptor(
        forKey key: String
    ) -> ThermostatStore.Descriptor.Temperature? {
        guard let value = thermostatNumericValue(forKey: key) else { return nil }
        return ThermostatStore.Descriptor.Temperature(
            value: value,
            unitSymbol: thermostatTemperatureUnitSymbol(forKey: key)
        )
    }

    private func thermostatNumericValue(forKey key: String) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }
        if let raw = data[key]?.stringValue {
            return Double(raw)
        }
        return nil
    }

    private func thermostatTemperatureUnitSymbol(forKey key: String) -> String? {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue,
            metadataObject?["unitLabel"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first {
            return normalizedThermostatTemperatureUnitSymbol(rawUnit)
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["temperatureUnit"]?.stringValue,
            data["tempUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first {
            return normalizedThermostatTemperatureUnitSymbol(rawUnit)
        }

        return nil
    }

    private func normalizedThermostatTemperatureUnitSymbol(_ raw: String) -> String? {
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

    private func thermostatHumidityUnitSymbol(forKey key: String) -> String? {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first {
            return normalizedThermostatHumidityUnitSymbol(rawUnit)
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["humidityUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first {
            return normalizedThermostatHumidityUnitSymbol(rawUnit)
        }

        return nil
    }

    private func normalizedThermostatHumidityUnitSymbol(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else { return nil }

        switch trimmed.lowercased() {
        case "na", "n/a", "none", "null", "-":
            return nil
        case "%", "percent", "percentage", "pct":
            return "%"
        default:
            return trimmed
        }
    }

    private static func isLikelyThermostatTemperatureKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.hasPrefix("config") { return false }
        if normalized == "lightpower" || normalized == "jobsmp" { return false }
        return normalized.contains("temp") || normalized.contains("temperature")
    }

    private static func isLikelyThermostatSetpointKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.hasPrefix("min") || normalized.hasPrefix("max") {
            return false
        }
        return normalized.contains("setpoint")
    }

    private static func isLikelyThermostatHumidityKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("hygro") || normalized.contains("humidity")
    }

    private static let preferredThermostatTemperatureKeys = [
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

    private static let preferredThermostatHumidityKeys = [
        "hygroIn",
        "humidity",
        "hygrometry",
        "humidityIn",
        "relativeHumidity"
    ]
}
