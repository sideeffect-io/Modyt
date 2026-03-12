import Foundation

struct ReorderDashboardFavoriteEffectExecutor: Sendable {
    let reorderFavorite: @Sendable (FavoriteType, FavoriteType) async -> Void

    @concurrent
    func callAsFunction(
        source: FavoriteType,
        target: FavoriteType
    ) async {
        await reorderFavorite(source, target)
    }
}
