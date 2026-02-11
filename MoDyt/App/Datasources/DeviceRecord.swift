import Foundation
import DeltaDoreClient

struct DeviceRecord: Codable, Identifiable, Sendable, Equatable {
    let uniqueId: String
    let deviceId: Int
    let endpointId: Int
    var name: String
    var usage: String
    var kind: String
    var data: [String: JSONValue]
    var metadata: [String: JSONValue]?
    var isFavorite: Bool
    var favoriteOrder: Int?
    var dashboardOrder: Int?
    var updatedAt: Date

    var id: String { uniqueId }
}

enum DeviceGroup: String, CaseIterable, Sendable {
    case shutter
    case window
    case door
    case garage
    case gate
    case light
    case energy
    case smoke
    case boiler
    case alarm
    case weather
    case water
    case thermo
    case other

    var title: String {
        switch self {
        case .shutter: return "Shutters"
        case .window: return "Windows"
        case .door: return "Doors"
        case .garage: return "Garage"
        case .gate: return "Gates"
        case .light: return "Lights"
        case .energy: return "Energy"
        case .smoke: return "Smoke"
        case .boiler: return "Boilers"
        case .alarm: return "Alarm"
        case .weather: return "Weather"
        case .water: return "Water"
        case .thermo: return "Thermo"
        case .other: return "Other"
        }
    }

    var symbolName: String {
        switch self {
        case .shutter: return "window.horizontal"
        case .window: return "rectangle.portrait"
        case .door: return "door.left.hand.open"
        case .garage: return "car"
        case .gate: return "square.split.2x2"
        case .light: return "lightbulb"
        case .energy: return "bolt"
        case .smoke: return "smoke"
        case .boiler: return "thermometer"
        case .alarm: return "shield.lefthalf.filled"
        case .weather: return "cloud.sun"
        case .water: return "drop"
        case .thermo: return "thermometer.medium"
        case .other: return "square.dashed"
        }
    }

    static func from(usage: String) -> DeviceGroup {
        switch usage {
        case "shutter", "klineShutter", "awning", "swingShutter":
            return .shutter
        case "window", "windowFrench", "windowSliding", "klineWindowFrench", "klineWindowSliding":
            return .window
        case "belmDoor", "klineDoor":
            return .door
        case "garage_door":
            return .garage
        case "gate":
            return .gate
        case "light":
            return .light
        case "conso":
            return .energy
        case "sensorDFR":
            return .smoke
        case "boiler", "sh_hvac", "electric", "aeraulic", "re2020ControlBoiler":
            return .boiler
        case "alarm":
            return .alarm
        case "weather", "sunlight", "sensorSun", "sensorSunlight", "irradiance":
            return .weather
        case "sensorDF":
            return .water
        case "sensorThermo":
            return .thermo
        default:
            return .other
        }
    }
}

struct DeviceControlDescriptor: Sendable, Equatable {
    enum Kind: Sendable, Equatable {
        case toggle
        case slider
    }

    let kind: Kind
    let key: String
    let isOn: Bool
    let value: Double
    let range: ClosedRange<Double>
}

struct DrivingLightControlDescriptor: Sendable, Equatable {
    let powerKey: String?
    let levelKey: String?
    let isOn: Bool
    let level: Double
    let range: ClosedRange<Double>

    var normalizedLevel: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return isOn ? 1 : 0 }
        let normalized = (level - range.lowerBound) / span
        return min(max(normalized, 0), 1)
    }

    var percentage: Int {
        Int((normalizedLevel * 100).rounded())
    }
}

struct TemperatureDescriptor: Sendable, Equatable {
    let key: String
    let value: Double
    let unitSymbol: String?
}

struct HumidityDescriptor: Sendable, Equatable {
    let key: String
    let value: Double
    let unitSymbol: String?
}

struct ThermostatDescriptor: Sendable, Equatable {
    let temperature: TemperatureDescriptor?
    let humidity: HumidityDescriptor?
    let setpointKey: String?
    let setpoint: Double?
    let setpointRange: ClosedRange<Double>
    let setpointStep: Double
    let unitSymbol: String?

    var canAdjustSetpoint: Bool {
        setpointKey != nil && setpoint != nil
    }
}

struct SunlightDescriptor: Sendable, Equatable {
    let key: String
    let value: Double
    let range: ClosedRange<Double>
    let unitSymbol: String

    var clampedValue: Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    var normalizedValue: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (clampedValue - range.lowerBound) / span
    }
}

struct EnergyConsumptionDescriptor: Sendable, Equatable {
    let key: String
    let value: Double
    let range: ClosedRange<Double>
    let unitSymbol: String

    var clampedValue: Double {
        min(max(value, range.lowerBound), range.upperBound)
    }

    var normalizedValue: Double {
        let span = range.upperBound - range.lowerBound
        guard span > 0 else { return 0 }
        return (clampedValue - range.lowerBound) / span
    }
}

extension DeviceRecord {
    struct ObservationSignature: Sendable, Equatable {
        let uniqueId: String
        let name: String
        let usage: String
        let kind: String
        let isFavorite: Bool
        let favoriteOrder: Int?
        let dashboardOrder: Int?
        let primaryControl: DeviceControlDescriptor?
        let drivingLightControl: DrivingLightControlDescriptor?
        let temperature: TemperatureDescriptor?
        let thermostat: ThermostatDescriptor?
        let sunlight: SunlightDescriptor?
        let energyConsumption: EnergyConsumptionDescriptor?
        let fallbackData: [String: JSONValue]?
    }

    struct FavoritesSignature: Sendable, Equatable {
        let uniqueId: String
        let name: String
        let usage: String
        let kind: String
        let isFavorite: Bool
        let favoriteOrder: Int?
        let dashboardOrder: Int?
        let primaryControl: DeviceControlDescriptor?
        let drivingLightControl: DrivingLightControlDescriptor?
        let temperature: TemperatureDescriptor?
        let thermostat: ThermostatDescriptor?
        let sunlight: SunlightDescriptor?
        let energyConsumption: EnergyConsumptionDescriptor?
        let fallbackStatusData: [String: JSONValue]?
    }

    var observationSignature: ObservationSignature {
        let primaryControl = primaryControlDescriptor()
        let drivingLightControl = drivingLightControlDescriptor()
        let temperature = temperatureDescriptor()
        let thermostat = thermostatDescriptor()
        let sunlight = sunlightDescriptor()
        let energyConsumption = energyConsumptionDescriptor()
        let fallbackData: [String: JSONValue]? =
            (primaryControl == nil
            && drivingLightControl == nil
            && temperature == nil
            && thermostat == nil
            && sunlight == nil
            && energyConsumption == nil) ? data : nil

        return ObservationSignature(
            uniqueId: uniqueId,
            name: name,
            usage: usage,
            kind: kind,
            isFavorite: isFavorite,
            favoriteOrder: favoriteOrder,
            dashboardOrder: dashboardOrder,
            primaryControl: primaryControl,
            drivingLightControl: drivingLightControl,
            temperature: temperature,
            thermostat: thermostat,
            sunlight: sunlight,
            energyConsumption: energyConsumption,
            fallbackData: fallbackData
        )
    }

    var favoritesSignature: FavoritesSignature {
        let primaryControl = primaryControlDescriptor()
        let drivingLightControl = drivingLightControlDescriptor()
        let temperature = temperatureDescriptor()
        let thermostat = thermostatDescriptor()
        let sunlight = sunlightDescriptor()
        let energyConsumption = energyConsumptionDescriptor()
        let fallbackStatusData: [String: JSONValue]? =
            group == .light
            || group == .shutter
            || group == .boiler
            || sunlight != nil
            || energyConsumption != nil ? nil : data

        return FavoritesSignature(
            uniqueId: uniqueId,
            name: name,
            usage: usage,
            kind: kind,
            isFavorite: isFavorite,
            favoriteOrder: favoriteOrder,
            dashboardOrder: dashboardOrder,
            primaryControl: primaryControl,
            drivingLightControl: drivingLightControl,
            temperature: temperature,
            thermostat: thermostat,
            sunlight: sunlight,
            energyConsumption: energyConsumption,
            fallbackStatusData: fallbackStatusData
        )
    }

    func isEquivalentForObservation(to other: DeviceRecord) -> Bool {
        observationSignature == other.observationSignature
    }

    func isEquivalentForFavorites(to other: DeviceRecord) -> Bool {
        favoritesSignature == other.favoritesSignature
    }

    var group: DeviceGroup {
        DeviceGroup.from(usage: usage)
    }

    var displayKind: String {
        kind.isEmpty ? usage : kind
    }

    func primaryControlDescriptor() -> DeviceControlDescriptor? {
        if let descriptor = sliderDescriptor(forKey: "level") {
            return descriptor
        }
        if let descriptor = sliderDescriptor(forKey: "position") {
            return descriptor
        }
        if let descriptor = toggleDescriptor(forKey: "open") {
            return descriptor
        }
        if let descriptor = toggleDescriptor(forKey: "on") {
            return descriptor
        }
        if let descriptor = toggleDescriptor(forKey: "state") {
            return descriptor
        }
        if let descriptor = firstBoolDescriptor() {
            return descriptor
        }
        if let descriptor = firstNumberDescriptor() {
            return descriptor
        }
        return nil
    }

    func drivingLightControlDescriptor() -> DrivingLightControlDescriptor? {
        guard group == .light else { return nil }

        let power = toggleDescriptor(forKey: "on")
            ?? toggleDescriptor(forKey: "state")
            ?? firstBoolDescriptor()

        let level = sliderDescriptor(forKey: "level")
            ?? sliderDescriptor(forKey: "position")
            ?? firstNumberDescriptor()

        guard power != nil || level != nil else { return nil }

        let range = level?.range ?? 0...100
        let lowerBound = range.lowerBound
        let upperBound = range.upperBound
        let fallbackLevel = power?.isOn == true ? upperBound : lowerBound
        let rawLevel = level?.value ?? fallbackLevel
        let levelValue = min(max(rawLevel, lowerBound), upperBound)
        let isOn = power?.isOn ?? (levelValue > lowerBound)

        return DrivingLightControlDescriptor(
            powerKey: power?.key,
            levelKey: level?.key,
            isOn: isOn,
            level: levelValue,
            range: range
        )
    }

    func temperatureDescriptor() -> TemperatureDescriptor? {
        guard group == .thermo || group == .boiler || thermostatDescriptor() != nil else { return nil }

        for key in Self.preferredTemperatureKeys {
            if let descriptor = temperatureDescriptor(forKey: key) {
                return descriptor
            }
        }

        // Fall back only to values that are explicitly temperature-like
        // and avoid configuration fields such as configTemp (often "NA"/non-display values).
        for key in data.keys.sorted() {
            guard Self.isLikelyTemperatureKey(key) else { continue }
            guard let descriptor = temperatureDescriptor(forKey: key) else { continue }
            if descriptor.unitSymbol != nil || key.localizedCaseInsensitiveContains("temperature") {
                return descriptor
            }
        }

        return nil
    }

    func humidityDescriptor() -> HumidityDescriptor? {
        for key in Self.preferredHumidityKeys {
            guard let value = numericValue(forKey: key) else { continue }
            let unitSymbol = humidityUnitSymbol(forKey: key) ?? "%"
            return HumidityDescriptor(
                key: key,
                value: value,
                unitSymbol: unitSymbol
            )
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyHumidityKey(key) else { continue }
            guard let value = numericValue(forKey: key) else { continue }
            let unitSymbol = humidityUnitSymbol(forKey: key) ?? "%"
            return HumidityDescriptor(
                key: key,
                value: value,
                unitSymbol: unitSymbol
            )
        }

        return nil
    }

    func thermostatDescriptor() -> ThermostatDescriptor? {
        guard group == .boiler || group == .thermo || isLikelyThermostatPayload() else {
            return nil
        }

        let setpoint = thermostatSetpointDescriptor()
        let temperature = thermostatTemperatureDescriptor()
        let humidity = humidityDescriptor()

        guard setpoint != nil || temperature != nil || humidity != nil else {
            return nil
        }

        return ThermostatDescriptor(
            temperature: temperature,
            humidity: humidity,
            setpointKey: setpoint?.key,
            setpoint: setpoint?.value,
            setpointRange: setpoint?.range ?? 5...30,
            setpointStep: setpoint?.step ?? 0.5,
            unitSymbol: setpoint?.unitSymbol ?? temperature?.unitSymbol
        )
    }

    func sunlightDescriptor() -> SunlightDescriptor? {
        guard group == .weather || group == .other else { return nil }

        for key in Self.preferredSunlightKeys {
            if let descriptor = sunlightDescriptor(forKey: key) {
                return descriptor
            }
        }

        for key in data.keys.sorted() {
            guard Self.isLikelySunlightKey(key) else { continue }
            guard let descriptor = sunlightDescriptor(forKey: key) else { continue }
            return descriptor
        }

        return nil
    }

    func energyConsumptionDescriptor() -> EnergyConsumptionDescriptor? {
        guard group == .energy || group == .other else { return nil }

        for key in Self.preferredEnergyConsumptionKeys {
            if let descriptor = energyConsumptionDescriptor(forKey: key) {
                return descriptor
            }
        }

        for key in data.keys.sorted() {
            guard Self.isLikelyEnergyConsumptionKey(key) else { continue }
            guard let descriptor = energyConsumptionDescriptor(forKey: key) else { continue }
            return descriptor
        }

        return nil
    }

    var statusText: String {
        if let value = data["level"]?.numberValue {
            return "Level \(Int(value))%"
        }
        if let value = data["position"]?.numberValue {
            return "Position \(Int(value))%"
        }
        if let value = data["open"]?.boolValue {
            return value ? "Open" : "Closed"
        }
        if let value = data["on"]?.boolValue {
            return value ? "On" : "Off"
        }
        if let value = data["state"]?.boolValue {
            return value ? "On" : "Off"
        }
        return "Updated \(relativeUpdateText)"
    }

    private var relativeUpdateText: String {
        let interval = Date().timeIntervalSince(updatedAt)
        if interval < 60 {
            return "just now"
        }
        let minutes = Int(interval / 60)
        if minutes < 60 {
            return "\(minutes)m ago"
        }
        let hours = Int(interval / 3600)
        return "\(hours)h ago"
    }

    private func sliderDescriptor(forKey key: String) -> DeviceControlDescriptor? {
        guard let value = numericValue(forKey: key) else { return nil }
        let range = metadataRange(forKey: key) ?? 0...100
        return DeviceControlDescriptor(kind: .slider, key: key, isOn: value > 0, value: value, range: range)
    }

    private func toggleDescriptor(forKey key: String) -> DeviceControlDescriptor? {
        guard let value = data[key]?.boolValue else { return nil }
        return DeviceControlDescriptor(kind: .toggle, key: key, isOn: value, value: value ? 1 : 0, range: 0...1)
    }

    private func firstBoolDescriptor() -> DeviceControlDescriptor? {
        for (key, value) in data {
            if let boolValue = value.boolValue {
                return DeviceControlDescriptor(kind: .toggle, key: key, isOn: boolValue, value: boolValue ? 1 : 0, range: 0...1)
            }
        }
        return nil
    }

    private func firstNumberDescriptor() -> DeviceControlDescriptor? {
        for (key, value) in data {
            if let numberValue = value.numberValue ?? value.stringValue.flatMap(Double.init) {
                let range = metadataRange(forKey: key) ?? 0...100
                return DeviceControlDescriptor(kind: .slider, key: key, isOn: numberValue > 0, value: numberValue, range: range)
            }
        }
        return nil
    }

    private func numericValue(forKey key: String) -> Double? {
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

    private func temperatureDescriptor(forKey key: String) -> TemperatureDescriptor? {
        guard let value = numericValue(forKey: key) else { return nil }
        return TemperatureDescriptor(
            key: key,
            value: value,
            unitSymbol: temperatureUnitSymbol(forKey: key)
        )
    }

    private func sunlightDescriptor(forKey key: String) -> SunlightDescriptor? {
        guard let rawValue = numericValue(forKey: key) else { return nil }

        let unit = sunlightUnit(forKey: key)
        let value = rawValue * unit.multiplier

        return SunlightDescriptor(
            key: key,
            value: value,
            range: Self.defaultSunlightRange,
            unitSymbol: unit.symbol
        )
    }

    private func energyConsumptionDescriptor(forKey key: String) -> EnergyConsumptionDescriptor? {
        guard let rawValue = numericValue(forKey: key) else { return nil }

        let unit = energyConsumptionUnit(forKey: key)
        let value = rawValue * unit.multiplier

        return EnergyConsumptionDescriptor(
            key: key,
            value: value,
            range: Self.defaultEnergyConsumptionRange,
            unitSymbol: unit.symbol
        )
    }

    private func temperatureUnitSymbol(forKey key: String) -> String? {
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
        guard !trimmed.isEmpty else { return nil }

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

    private func humidityUnitSymbol(forKey key: String) -> String? {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first {
            return normalizedHumidityUnitSymbol(rawUnit)
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["humidityUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first {
            return normalizedHumidityUnitSymbol(rawUnit)
        }

        return nil
    }

    private func normalizedHumidityUnitSymbol(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        switch trimmed.lowercased() {
        case "na", "n/a", "none", "null", "-":
            return nil
        case "%", "percent", "percentage", "pct":
            return "%"
        default:
            return trimmed
        }
    }

    private struct SunlightUnit {
        let symbol: String
        let multiplier: Double
    }

    private struct EnergyConsumptionUnit {
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
        guard !trimmed.isEmpty else { return nil }

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

    private func energyConsumptionUnit(forKey key: String) -> EnergyConsumptionUnit {
        let metadataObject = metadata?[key]?.objectValue
        let metadataCandidates = [
            metadataObject?["unit"]?.stringValue,
            metadataObject?["unity"]?.stringValue,
            metadataObject?["symbol"]?.stringValue,
            metadataObject?["uom"]?.stringValue
        ]

        if let rawUnit = metadataCandidates.compactMap({ $0 }).first,
           let unit = normalizedEnergyConsumptionUnit(rawUnit) {
            return unit
        }

        let dataCandidates = [
            data["\(key)_unit"]?.stringValue,
            data["\(key)Unit"]?.stringValue,
            data["energyUnit"]?.stringValue,
            data["consumptionUnit"]?.stringValue,
            data["unit"]?.stringValue
        ]

        if let rawUnit = dataCandidates.compactMap({ $0 }).first,
           let unit = normalizedEnergyConsumptionUnit(rawUnit) {
            return unit
        }

        return EnergyConsumptionUnit(symbol: "kWh", multiplier: 1)
    }

    private func normalizedEnergyConsumptionUnit(_ raw: String) -> EnergyConsumptionUnit? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let canonical = trimmed
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: ".", with: "")

        switch canonical {
        case "na", "n/a", "none", "null", "-":
            return nil
        case "kwh", "kilowatthour", "kilowatthours":
            return EnergyConsumptionUnit(symbol: "kWh", multiplier: 1)
        case "wh", "watthour", "watthours":
            return EnergyConsumptionUnit(symbol: "kWh", multiplier: 0.001)
        case "mwh", "megawatthour", "megawatthours":
            return EnergyConsumptionUnit(symbol: "kWh", multiplier: 1000)
        default:
            return EnergyConsumptionUnit(symbol: trimmed, multiplier: 1)
        }
    }

    private func thermostatTemperatureDescriptor() -> TemperatureDescriptor? {
        for key in Self.preferredThermostatTemperatureKeys {
            if let descriptor = temperatureDescriptor(forKey: key) {
                return descriptor
            }
        }
        return nil
    }

    private func isLikelyThermostatPayload() -> Bool {
        for key in data.keys {
            if Self.isLikelySetpointKey(key) || Self.isLikelyHumidityKey(key) {
                return true
            }
        }
        return false
    }

    private struct ThermostatSetpointDescriptor {
        let key: String
        let value: Double
        let range: ClosedRange<Double>
        let step: Double
        let unitSymbol: String?
    }

    private func thermostatSetpointDescriptor() -> ThermostatSetpointDescriptor? {
        for key in Self.preferredSetpointKeys {
            guard let value = numericValue(forKey: key) else { continue }
            return ThermostatSetpointDescriptor(
                key: key,
                value: value,
                range: thermostatSetpointRange(forKey: key),
                step: thermostatSetpointStep(forKey: key),
                unitSymbol: temperatureUnitSymbol(forKey: key)
            )
        }

        for key in data.keys.sorted() {
            guard Self.isLikelySetpointKey(key) else { continue }
            guard let value = numericValue(forKey: key) else { continue }
            return ThermostatSetpointDescriptor(
                key: key,
                value: value,
                range: thermostatSetpointRange(forKey: key),
                step: thermostatSetpointStep(forKey: key),
                unitSymbol: temperatureUnitSymbol(forKey: key)
            )
        }

        return nil
    }

    private func thermostatSetpointRange(forKey key: String) -> ClosedRange<Double> {
        if let metadataRange = metadataRange(forKey: key) {
            return metadataRange
        }

        if let companionRange = thermostatCompanionRange(forKey: key) {
            return companionRange
        }

        return 5...30
    }

    private func thermostatCompanionRange(forKey key: String) -> ClosedRange<Double>? {
        let companionKeys: (min: String, max: String)
        switch key {
        case "heatSetpoint":
            companionKeys = ("minHeatSetpoint", "maxHeatSetpoint")
        case "coolSetpoint":
            companionKeys = ("minCoolSetpoint", "maxCoolSetpoint")
        default:
            companionKeys = ("minSetpoint", "maxSetpoint")
        }

        guard let minValue = numericValue(forKey: companionKeys.min),
              let maxValue = numericValue(forKey: companionKeys.max),
              minValue < maxValue else {
            return nil
        }
        return minValue...maxValue
    }

    private func thermostatSetpointStep(forKey key: String) -> Double {
        if let metadataStep = metadata?[key]?.objectValue?["step"]?.numberValue,
           metadataStep > 0 {
            return metadataStep
        }
        return 0.5
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
        "ambientTemperature",
        "measuredTemperature",
        "regTemperature",
        "devTemperature"
    ]

    private static let preferredThermostatTemperatureKeys = [
        "temperature",
        "ambientTemperature",
        "regTemperature",
        "devTemperature",
        "currentTemperature",
        "outTemperature"
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

    private static let preferredHumidityKeys = [
        "hygroIn",
        "humidity",
        "hygrometry",
        "humidityIn",
        "relativeHumidity"
    ]

    private static let preferredSunlightKeys = [
        "lightPower",
        "sunlightPower",
        "sunlight",
        "solarRadiation",
        "solarIrradiance",
        "irradiance",
        "globalRadiation"
    ]

    private static let preferredEnergyConsumptionKeys = [
        "energyIndex_ELEC",
        "energyIndex",
        "energyHisto_ELEC",
        "energyHisto",
        "consumption",
        "energy"
    ]

    private static let defaultSunlightRange: ClosedRange<Double> = 0...1400
    // 36 kVA (typical residential max in France) used continuously for 24h ~= 864 kWh/day.
    private static let defaultEnergyConsumptionRange: ClosedRange<Double> = 0...864

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

    private static func isLikelySunlightKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        return normalized == "lightpower"
            || normalized.contains("sun")
            || normalized.contains("solar")
            || normalized.contains("irradiance")
            || normalized.contains("radiation")
    }

    private static func isLikelyEnergyConsumptionKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.contains("energyinstant") {
            return false
        }

        return normalized.contains("energyindex")
            || normalized.contains("energyhisto")
            || normalized.contains("consumption")
            || normalized.contains("kwh")
            || normalized.contains("energy")
    }
}
