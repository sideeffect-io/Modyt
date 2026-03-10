import Foundation

enum LightPreset: String, CaseIterable, Identifiable, Sendable {
    case on
    case half
    case off

    var id: String { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .on:
            return "On"
        case .half:
            return "Half"
        case .off:
            return "Off"
        }
    }
}
