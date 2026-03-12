import Foundation

struct CheckMainGatewayConnectionEffectExecutor: Sendable {
    let checkGatewayConnection: @Sendable () async -> MainEvent?

    @concurrent
    func callAsFunction() async -> MainEvent? {
        await checkGatewayConnection()
    }
}
