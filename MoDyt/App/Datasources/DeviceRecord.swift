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
        case "boiler", "sh_hvac", "electric", "aeraulic":
            return .boiler
        case "alarm":
            return .alarm
        case "weather":
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
        let fallbackStatusData: [String: JSONValue]?
    }

    var observationSignature: ObservationSignature {
        let primaryControl = primaryControlDescriptor()
        let drivingLightControl = drivingLightControlDescriptor()
        let temperature = temperatureDescriptor()
        let fallbackData: [String: JSONValue]? =
            (primaryControl == nil && drivingLightControl == nil && temperature == nil) ? data : nil

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
            fallbackData: fallbackData
        )
    }

    var favoritesSignature: FavoritesSignature {
        let primaryControl = primaryControlDescriptor()
        let drivingLightControl = drivingLightControlDescriptor()
        let temperature = temperatureDescriptor()
        let fallbackStatusData: [String: JSONValue]? = group == .light || group == .shutter ? nil : data

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
        guard group == .thermo else { return nil }

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
        guard let value = data[key]?.numberValue else { return nil }
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
            if let numberValue = value.numberValue {
                let range = metadataRange(forKey: key) ?? 0...100
                return DeviceControlDescriptor(kind: .slider, key: key, isOn: numberValue > 0, value: numberValue, range: range)
            }
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
        guard let value = data[key]?.numberValue else { return nil }
        return TemperatureDescriptor(
            key: key,
            value: value,
            unitSymbol: temperatureUnitSymbol(forKey: key)
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

    private static let preferredTemperatureKeys = [
        "outTemperature",
        "temperature",
        "temp",
        "currentTemperature",
        "outdoorTemperature",
        "outsideTemperature",
        "ambientTemperature",
        "measuredTemperature",
        "regTemperature",
        "devTemperature"
    ]

    private static func isLikelyTemperatureKey(_ key: String) -> Bool {
        let normalized = key.lowercased()
        if normalized.hasPrefix("config") { return false }
        if normalized == "lightpower" || normalized == "jobsmp" { return false }
        return normalized.contains("temp") || normalized.contains("temperature")
    }
}
