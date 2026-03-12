import Foundation

struct SetMainAppActiveEffectExecutor: Sendable {
    let setAppActive: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async {
        await setAppActive()
    }
}
