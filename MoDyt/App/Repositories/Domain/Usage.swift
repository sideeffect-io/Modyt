import Foundation

enum Usage: String, CaseIterable, Sendable, Equatable, Codable {
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
    case scene
    case other

    static func from(usage: String) -> Usage {
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
        case "scene":
            return .scene
        default:
            return .other
        }
    }
}
