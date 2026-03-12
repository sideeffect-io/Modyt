import Foundation

struct ToggleDeviceFavoriteEffectExecutor: Sendable {
    let toggleFavorite: @Sendable (DeviceIdentifier) async -> Void

    @concurrent
    func callAsFunction(_ identifier: DeviceIdentifier) async {
        await toggleFavorite(identifier)
    }
}
