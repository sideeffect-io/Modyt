import Foundation

struct DisconnectMainEffectExecutor: Sendable {
    let disconnect: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async -> MainEvent? {
        await disconnect()
        return .disconnectionWasSuccessful
    }
}
