import Foundation

struct RefreshDevicesEffectExecutor: Sendable {
    let refreshAll: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async {
        await refreshAll()
    }
}
