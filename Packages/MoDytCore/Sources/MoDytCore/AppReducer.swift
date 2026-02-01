import Foundation

public enum AppReducer {
    public static func reduce(state: AppState, event: AppEvent) -> Transition<AppState, AppEffect> {
        var next = state
        var effects: [AppEffect] = []

        switch event {
        case .onAppear:
            if case .idle = state.authStatus {
                next.authStatus = .connecting
                effects.append(.connect(.auto))
                effects.append(.loadInitialData)
            }

        case .connectRequested:
            next.authStatus = .connecting
            next.errorMessage = nil
            effects.append(.connect(.credentials(state.authForm)))

        case .connectSucceeded:
            next.authStatus = .connected
            next.errorMessage = nil
            effects.append(.startMessageStream)
            effects.append(.loadInitialData)

        case .connectFailed(let message):
            next.authStatus = .needsCredentials
            next.errorMessage = message

        case .disconnectRequested:
            next.authStatus = .connecting
            effects.append(.disconnect)

        case .disconnected:
            next.authStatus = .needsCredentials
            next.errorMessage = nil

        case .authFormUpdated(let form):
            next.authForm = form

        case .siteSelectionRequested(let sites):
            next.authStatus = .selectingSite(sites)

        case .siteSelected(let index):
            next.authStatus = .connecting
            effects.append(.provideSiteSelection(index))

        case .devicesLoaded(let devices):
            next.devices = devices

        case .dashboardLayoutLoaded(let layout):
            next.dashboardLayout = layout

        case .dashboardLayoutUpdated(let layout):
            next.dashboardLayout = layout
            effects.append(.persistLayout(layout))

        case .dashboardEditingChanged(let isEditing):
            next.isDashboardEditing = isEditing

        case .appModeChanged(let mode):
            next.mode = mode

        case .deviceAction(let device):
            effects.append(.sendDeviceCommand(device))

        case .favoriteToggled(let deviceId, let isFavorite):
            var devices = next.devices
            if let index = devices.firstIndex(where: { $0.id == deviceId }) {
                let device = devices[index]
                devices[index] = DeviceSummary(
                    id: device.id,
                    deviceId: device.deviceId,
                    endpointId: device.endpointId,
                    name: device.name,
                    usage: device.usage,
                    kind: device.kind,
                    primaryState: device.primaryState,
                    primaryValueText: device.primaryValueText,
                    isFavorite: isFavorite
                )
            }
            next.devices = devices
            effects.append(.persistFavorite(deviceId, isFavorite))

        case .setAppActive(let isActive):
            effects.append(.setAppActive(isActive))

        case .errorCleared:
            next.errorMessage = nil
        }

        return Transition(state: next, effects: effects)
    }
}

public struct Transition<State, Effect> {
    public let state: State
    public let effects: [Effect]

    public init(state: State, effects: [Effect]) {
        self.state = state
        self.effects = effects
    }
}
