import Foundation

struct SetMainAppInactiveEffectExecutor: Sendable {
    let setAppInactive: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async {
        await setAppInactive()
    }
}
