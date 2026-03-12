import Foundation

struct RequestDisconnectEffectExecutor: Sendable {
    let requestDisconnect: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async -> SettingsEvent? {
        await requestDisconnect()
        return .disconnectFinished
    }
}
