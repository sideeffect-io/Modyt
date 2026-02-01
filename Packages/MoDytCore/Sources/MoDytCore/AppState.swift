import Foundation

public struct AppState: Equatable, Sendable {
    public var authStatus: AuthStatus
    public var authForm: AuthForm
    public var mode: AppMode
    public var devices: [DeviceSummary]
    public var dashboardLayout: [DashboardPlacement]
    public var isDashboardEditing: Bool
    public var errorMessage: String?

    public init(
        authStatus: AuthStatus,
        authForm: AuthForm,
        mode: AppMode,
        devices: [DeviceSummary],
        dashboardLayout: [DashboardPlacement],
        isDashboardEditing: Bool,
        errorMessage: String?
    ) {
        self.authStatus = authStatus
        self.authForm = authForm
        self.mode = mode
        self.devices = devices
        self.dashboardLayout = dashboardLayout
        self.isDashboardEditing = isDashboardEditing
        self.errorMessage = errorMessage
    }

    public static func initial() -> AppState {
        AppState(
            authStatus: .idle,
            authForm: AuthForm(),
            mode: .dashboard,
            devices: [],
            dashboardLayout: [],
            isDashboardEditing: false,
            errorMessage: nil
        )
    }
}

public enum AppMode: String, Equatable, Sendable, CaseIterable {
    case dashboard
    case complete
}

public enum AuthStatus: Equatable, Sendable {
    case idle
    case connecting
    case needsCredentials
    case selectingSite([SiteInfo])
    case connected
    case error(String)
}
