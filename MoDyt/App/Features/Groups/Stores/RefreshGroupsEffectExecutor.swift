import Foundation

struct RefreshGroupsEffectExecutor: Sendable {
    let refreshAll: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async {
        await refreshAll()
    }
}
