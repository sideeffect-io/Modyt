import Foundation

extension Device {
    struct ClimateTemperatureSignal: Sendable, Equatable {
        let key: String
        let value: Double
        let unitSymbol: String?
    }

    struct ClimateHumiditySignal: Sendable, Equatable {
        let key: String
        let value: Double
        let unitSymbol: String?
    }

    var hasLikelyClimatePayload: Bool {
        data.keys.contains { key in
            Self.isLikelyClimateSetpointKey(key) || Self.isLikelyClimateHumidityKey(key)
        }
    }

    var hasLikelyHeatPumpPayload: Bool {
        let lowercasedKeys = Set(data.keys.map { $0.lowercased() })
        return lowercasedKeys.contains(where: Self.heatPumpSignalKeys.contains)
    }

    func climateCurrentTemperatureSignal() -> ClimateTemperatureSignal? {
        for key in Self.preferredClimateTemperatureKeys {
            if let signal = climateTemperatureSignal(forKey: key) {
                return signal
            }
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyClimateTemperatureKey(key) else { continue }
            guard let signal = climateTemperatureSignal(forKey: key) else { continue }
            if signal.unitSymbol != nil
                || key.localizedCaseInsensitiveContains("temperature")
                || Self.heatPumpTemperatureFallbackKeys.contains(key.lowercased()) {
                return signal
            }
        }

        return nil
    }

    func climateSetpointSignal() -> ClimateTemperatureSignal? {
        for key in Self.preferredClimateSetpointKeys {
            if let signal = climateSetpointSignal(forKey: key) {
                return signal
            }
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyClimateSetpointKey(key) else { continue }
            guard let signal = climateSetpointSignal(forKey: key) else { continue }
            return signal
        }

        return nil
    }

    func climateHumiditySignal() -> ClimateHumiditySignal? {
        for key in Self.preferredClimateHumidityKeys {
            guard let value = climateNumericValue(forKey: key) else { continue }
            return ClimateHumiditySignal(
                key: key,
                value: value,
                unitSymbol: climateHumidityUnitSymbol(forKey: key) ?? "%"
            )
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyClimateHumidityKey(key) else { continue }
            guard let value = climateNumericValue(forKey: key) else { continue }
            return ClimateHumiditySignal(
                key: key,
                value: value,
                unitSymbol: climateHumidityUnitSymbol(forKey: key) ?? "%"
            )
        }

        return nil
    }

    func climateNumericValue(forKey key: String) -> Double? {
        if let value = data[key]?.numberValue {
            return value
        }

        if let raw = data[key]?.stringValue {
            return Double(raw)
        }

        return nil
    }

    func climateTemperatureSignal(forKey key: String) -> ClimateTemperatureSignal? {
        guard let value = climateNumericValue(forKey: key) else { return nil }
        return ClimateTemperatureSignal(
            key: key,
            value: value,
            unitSymbol: climateTemperatureUnitSymbol(forKey: key)
        )
    }

    func climateSetpointSignal(forKey key: String) -> ClimateTemperatureSignal? {
        guard let value = climateNumericValue(forKey: key) else { return nil }
        return ClimateTemperatureSignal(
            key: key,
            value: value,
            unitSymbol: climateTemperatureUnitSymbol(forKey: key)
        )
    }

    func climateTemperatureUnitSymbol(forKey key: String) -> String? {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue,
            metadataObject?["unitLabel"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first {
            return Self.normalizedTemperatureUnitSymbol(rawUnit)
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["temperatureUnit"]?.stringValue,
            data["tempUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first {
            return Self.normalizedTemperatureUnitSymbol(rawUnit)
        }

        return nil
    }

    func climateHumidityUnitSymbol(forKey key: String) -> String? {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first {
            return Self.normalizedHumidityUnitSymbol(rawUnit)
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["humidityUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first {
            return Self.normalizedHumidityUnitSymbol(rawUnit)
        }

        return nil
    }

    static func isLikelyClimateTemperatureKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.hasPrefix("config") { return false }
        if normalized == "lightpower" || normalized == "jobsmp" { return false }
        return normalized.contains("temp") || normalized.contains("temperature")
    }

    static func isLikelyClimateSetpointKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.hasPrefix("min") || normalized.hasPrefix("max") {
            return false
        }
        return normalized.contains("setpoint")
    }

    static func isLikelyClimateHumidityKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized.contains("hygro") || normalized.contains("humidity")
    }

    static func normalizedTemperatureUnitSymbol(_ raw: String) -> String? {
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

    static func normalizedHumidityUnitSymbol(_ raw: String) -> String? {
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

    static let preferredClimateTemperatureKeys = [
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

    static let preferredClimateSetpointKeys = [
        "setpoint",
        "currentSetpoint",
        "localSetpoint",
        "heatSetpoint",
        "coolSetpoint",
        "masterAbsSetpoint",
        "masterSchedSetpoint"
    ]

    static let preferredClimateHumidityKeys = [
        "hygroIn",
        "humidity",
        "hygrometry",
        "humidityIn",
        "relativeHumidity"
    ]

    static let heatPumpSignalKeys: Set<String> = [
        "regtemperature",
        "devtemperature",
        "currentsetpoint",
        "localsetpoint",
        "masterabssetpoint",
        "masterschedsetpoint",
        "waterflowreq",
        "boost",
        "booston"
    ]

    private static let heatPumpTemperatureFallbackKeys: Set<String> = [
        "regtemperature",
        "devtemperature",
        "ambienttemperature",
        "outtemperature"
    ]
}
