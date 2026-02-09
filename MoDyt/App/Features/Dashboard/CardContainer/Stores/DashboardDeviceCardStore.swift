import Observation

enum DashboardDeviceCardEvent: Sendable {
    case favoriteTapped
}

@Observable
@MainActor
final class DashboardDeviceCardStore {
    struct Dependencies {
        let toggleFavorite: (String) async -> Void
    }

    private let uniqueId: String
    private let dependencies: Dependencies

    init(uniqueId: String, dependencies: Dependencies) {
        self.uniqueId = uniqueId
        self.dependencies = dependencies
    }

    func send(_ event: DashboardDeviceCardEvent) {
        switch event {
        case .favoriteTapped:
            Task { [dependencies, uniqueId] in
                await dependencies.toggleFavorite(uniqueId)
            }
        }
    }
}
