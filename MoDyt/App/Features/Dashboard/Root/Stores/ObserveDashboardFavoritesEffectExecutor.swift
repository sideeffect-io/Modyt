import Foundation

struct ObserveDashboardFavoritesEffectExecutor: Sendable {
    let observeFavorites: @Sendable () async -> any AsyncSequence<DashboardFavoritesObservation, Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<DashboardEvent> {
        let stream = await observeFavorites()
        return makeEventStream(from: stream) { observation in
            .favoritesObserved(observation)
        }
    }
}
