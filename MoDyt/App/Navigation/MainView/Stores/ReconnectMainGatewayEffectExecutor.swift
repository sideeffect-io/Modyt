import Foundation

struct ReconnectMainGatewayEffectExecutor: Sendable {
    let reconnectToGateway: @Sendable () async -> MainEvent

    @concurrent
    func callAsFunction() async -> MainEvent? {
        await reconnectToGateway()
    }
}
