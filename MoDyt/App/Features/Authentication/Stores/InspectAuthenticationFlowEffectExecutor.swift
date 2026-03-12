import Foundation

struct InspectAuthenticationFlowEffectExecutor: Sendable {
    let inspectFlow: @Sendable () async -> AuthenticationFlowStatus

    @concurrent
    func callAsFunction() async -> AuthenticationEvent? {
        .flowInspected(await inspectFlow())
    }
}
