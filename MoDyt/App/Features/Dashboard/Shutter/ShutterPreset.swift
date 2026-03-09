import Foundation

enum ShutterPreset: Int, CaseIterable, Identifiable, Sendable {
    case open = 100
    case quarter = 75
    case half = 50
    case threeQuarter = 25
    case closed = 0

    var id: Int { rawValue }

    var accessibilityLabel: String {
        switch self {
        case .open:
            return "Open"
        case .quarter:
            return "Quarter"
        case .half:
            return "Half"
        case .threeQuarter:
            return "Three quarters"
        case .closed:
            return "Closed"
        }
    }
}
