enum ShutterControlLayout {
    case compact
    case list
    case regular

    var metrics: ShutterMetrics {
        switch self {
        case .compact:
            return .compact
        case .list:
            return .list
        case .regular:
            return .regular
        }
    }
}
