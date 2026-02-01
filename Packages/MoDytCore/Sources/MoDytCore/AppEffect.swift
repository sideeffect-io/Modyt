import Foundation

public enum AppEffect: Equatable, Sendable {
    case connect(ConnectRequest)
    case disconnect
    case loadInitialData
    case sendDeviceCommand(DeviceSummary)
    case persistFavorite(String, Bool)
    case persistLayout([DashboardPlacement])
    case provideSiteSelection(Int)
    case setAppActive(Bool)
    case startMessageStream
    case stopMessageStream
}

public enum ConnectRequest: Equatable, Sendable {
    case auto
    case credentials(AuthForm)
}
