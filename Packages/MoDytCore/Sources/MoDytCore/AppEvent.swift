import Foundation

public enum AppEvent: Equatable, Sendable {
    case onAppear
    case connectRequested
    case connectSucceeded
    case connectFailed(String)
    case disconnectRequested
    case disconnected
    case authFormUpdated(AuthForm)
    case siteSelectionRequested([SiteInfo])
    case siteSelected(Int)
    case devicesLoaded([DeviceSummary])
    case dashboardLayoutLoaded([DashboardPlacement])
    case dashboardLayoutUpdated([DashboardPlacement])
    case dashboardEditingChanged(Bool)
    case appModeChanged(AppMode)
    case deviceAction(DeviceSummary)
    case favoriteToggled(String, Bool)
    case setAppActive(Bool)
    case errorCleared
}
