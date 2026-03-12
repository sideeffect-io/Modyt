import Foundation

struct RefreshDashboardEffectExecutor: Sendable {
    let refreshAll: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async {
        await refreshAll()
    }
}
