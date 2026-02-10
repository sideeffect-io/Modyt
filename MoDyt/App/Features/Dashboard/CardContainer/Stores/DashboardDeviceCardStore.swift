import Observation

enum DashboardDeviceCardEvent: Sendable {
    case favoriteTapped
}

@Observable
@MainActor
final class DashboardDeviceCardStore {
    struct Dependencies {
        let toggleFavorite: @Sendable (String) async -> Void
    }

    private let uniqueId: String
    private let worker: Worker

    init(uniqueId: String, dependencies: Dependencies) {
        self.uniqueId = uniqueId
        self.worker = Worker(toggleFavorite: dependencies.toggleFavorite)
    }

    func send(_ event: DashboardDeviceCardEvent) {
        switch event {
        case .favoriteTapped:
            Task { [worker, uniqueId] in
                await worker.toggleFavorite(uniqueId)
            }
        }
    }

    private actor Worker {
        private let toggleFavoriteAction: @Sendable (String) async -> Void

        init(toggleFavorite: @escaping @Sendable (String) async -> Void) {
            self.toggleFavoriteAction = toggleFavorite
        }

        func toggleFavorite(_ uniqueId: String) async {
            await toggleFavoriteAction(uniqueId)
        }
    }
}
