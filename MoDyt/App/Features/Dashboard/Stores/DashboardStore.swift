import Foundation
import Observation

struct DashboardState: Sendable, Equatable {
    var favoriteIDs: [String]

    static let initial = DashboardState(favoriteIDs: [])
}

enum DashboardEvent: Sendable {
    case onAppear
    case favoritesUpdated([String])
    case refreshRequested
    case toggleFavorite(String)
    case reorderFavorite(String, String)
}

enum DashboardEffect: Sendable, Equatable {
    case startObservingFavorites
    case refreshAll
    case toggleFavorite(String)
    case reorderFavorite(String, String)
}

enum DashboardReducer {
    static func reduce(state: DashboardState, event: DashboardEvent) -> (DashboardState, [DashboardEffect]) {
        var state = state
        var effects: [DashboardEffect] = []

        switch event {
        case .onAppear:
            effects = [.startObservingFavorites]

        case .favoritesUpdated(let favoriteIDs):
            state.favoriteIDs = favoriteIDs

        case .refreshRequested:
            effects = [.refreshAll]

        case .toggleFavorite(let uniqueId):
            effects = [.toggleFavorite(uniqueId)]

        case .reorderFavorite(let sourceId, let targetId):
            effects = [.reorderFavorite(sourceId, targetId)]
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class DashboardStore {
    struct Dependencies {
        let observeFavoriteIDs: () -> AsyncStream<[String]>
        let toggleFavorite: (String) async -> Void
        let reorderFavorite: (String, String) async -> Void
        let refreshAll: () async -> Void
    }

    private(set) var state: DashboardState

    private let dependencies: Dependencies
    private let favoritesTask = TaskHandle()

    init(dependencies: Dependencies) {
        self.state = .initial
        self.dependencies = dependencies
    }

    func send(_ event: DashboardEvent) {
        let (nextState, effects) = DashboardReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [DashboardEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: DashboardEffect) {
        switch effect {
        case .startObservingFavorites:
            guard favoritesTask.task == nil else { return }
            favoritesTask.task = Task { [weak self, dependencies] in
                let stream = dependencies.observeFavoriteIDs()
                for await favoriteIDs in stream {
                    self?.send(.favoritesUpdated(favoriteIDs))
                }
            }

        case .refreshAll:
            Task { [dependencies] in
                await dependencies.refreshAll()
            }

        case .toggleFavorite(let uniqueId):
            Task { [dependencies] in
                await dependencies.toggleFavorite(uniqueId)
            }

        case .reorderFavorite(let sourceId, let targetId):
            Task { [dependencies] in
                await dependencies.reorderFavorite(sourceId, targetId)
            }
        }
    }
}

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
