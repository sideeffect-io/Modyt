import Foundation

struct ReadSettingsConnectionRouteEffectExecutor: Sendable {
    let readConnectionRoute: @Sendable () async -> SettingsConnectionRoute

    @concurrent
    func callAsFunction() async -> SettingsEvent? {
        .connectionRouteLoaded(await readConnectionRoute())
    }
}
