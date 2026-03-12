import Foundation

struct ToggleDashboardFavoriteEffectExecutor: Sendable {
    let toggleFavorite: @Sendable (FavoriteType) async -> Void

    @concurrent
    func callAsFunction(_ favoriteType: FavoriteType) async {
        await toggleFavorite(favoriteType)
    }
}
