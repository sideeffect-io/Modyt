import Foundation

extension Device {
    var controlKind: FavoriteControlKind {
        let normalizedUsage = usage
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        let resolvedUsage = self.resolvedUsage

        if resolvedUsage == .energy {
            return .energyConsumption
        }

        let signalKeys = Self.normalizedSignalKeys(data: data, metadata: metadata)
        let hasHeatPumpSignals = signalKeys.contains(where: Self.controlKindHeatPumpSignalKeys.contains)
        let hasThermostatSignals = signalKeys.contains(where: Self.controlKindThermostatSignalKeys.contains)
        let hasTemperatureSignals = signalKeys.contains(where: Self.controlKindTemperatureSignalKeys.contains)

        if hasHeatPumpSignals {
            return .heatPump
        }

        if normalizedUsage == "sh_hvac"
            || normalizedUsage == "aeraulic"
            || normalizedUsage.contains("hvac") {
            return .heatPump
        }

        if normalizedUsage == "sensorthermo" {
            return .temperature
        }

        if Self.thermostatUsageValues.contains(normalizedUsage) {
            return .thermostat
        }

        if hasThermostatSignals {
            return .thermostat
        }

        if hasTemperatureSignals {
            return .temperature
        }

        switch resolvedUsage {
        case .scene:
            return .scene
        case .shutter:
            return .shutter
        case .light:
            return .light
        case .thermo:
            return .temperature
        case .boiler:
            return .thermostat
        case .weather:
            return .sunlight
        case .energy:
            return .energyConsumption
        case .smoke:
            return .smoke
        default:
            return .unsupported
        }
    }

    private static func normalizedSignalKeys(
        data: [String: JSONValue],
        metadata: [String: JSONValue]?
    ) -> Set<String> {
        var keys = Set(data.keys.map { $0.lowercased() })
        if let metadata {
            keys.formUnion(metadata.keys.map { $0.lowercased() })
        }
        return keys
    }

    private static let thermostatUsageValues: Set<String> = [
        "boiler",
        "electric",
        "re2020controlboiler"
    ]

    private static let controlKindHeatPumpSignalKeys: Set<String> = [
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

    private static let controlKindThermostatSignalKeys: Set<String> = [
        "temperature",
        "setpoint",
        "authorization",
        "hvacmode",
        "thermiclevel",
        "outtemperature",
        "hygroin"
    ]

    private static let controlKindTemperatureSignalKeys: Set<String> = [
        "outtemperature",
        "ambienttemperature",
        "temperature",
        "regtemperature",
        "devtemperature",
        "currenttemperature",
        "measuredtemperature"
    ]
}
