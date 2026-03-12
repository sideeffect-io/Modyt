import Foundation

struct HandleMainGatewayMessagesEffectExecutor: Sendable {
    let handleGatewayMessages: @Sendable () async -> MainEvent

    @concurrent
    func callAsFunction() async -> MainEvent? {
        await handleGatewayMessages()
    }
}
