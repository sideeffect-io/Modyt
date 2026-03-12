import Foundation

struct RefreshScenesEffectExecutor: Sendable {
    let refreshAll: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async {
        await refreshAll()
    }
}
