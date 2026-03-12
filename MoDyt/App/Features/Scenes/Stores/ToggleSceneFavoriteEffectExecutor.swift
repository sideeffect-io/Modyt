import Foundation

struct ToggleSceneFavoriteEffectExecutor: Sendable {
    let toggleFavorite: @Sendable (String) async -> Void

    @concurrent
    func callAsFunction(_ identifier: String) async {
        await toggleFavorite(identifier)
    }
}
