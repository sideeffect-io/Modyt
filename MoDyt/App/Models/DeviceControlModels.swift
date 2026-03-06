import Foundation

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
