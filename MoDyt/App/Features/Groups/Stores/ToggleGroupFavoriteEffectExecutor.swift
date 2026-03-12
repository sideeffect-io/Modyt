import Foundation

struct ToggleGroupFavoriteEffectExecutor: Sendable {
    let toggleFavorite: @Sendable (String) async -> Void

    @concurrent
    func callAsFunction(_ identifier: String) async {
        await toggleFavorite(identifier)
    }
}
