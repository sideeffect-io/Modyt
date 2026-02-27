import Foundation

enum FavoriteControlKind: Sendable, Equatable {
    case scene
    case shutter
    case light
    case temperature
    case thermostat
    case heatPump
    case sunlight
    case energyConsumption
    case smoke
    case unsupported
}

extension FavoriteControlKind {
    static func from(usage: Usage) -> FavoriteControlKind {
        switch usage {
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
}
