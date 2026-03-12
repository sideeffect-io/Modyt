import Observation

enum DashboardDeviceCardEvent: Sendable {
    case favoriteTapped
}

struct DashboardDeviceCardState: Sendable, Equatable {
    static let initial = DashboardDeviceCardState()
}

enum DashboardDeviceCardEffect: Sendable, Equatable {
    case toggleFavorite
}

@Observable
@MainActor
final class DashboardDeviceCardStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: DashboardDeviceCardState,
            _ event: DashboardDeviceCardEvent,
            favoriteType _: FavoriteType
        ) -> Transition<DashboardDeviceCardState, DashboardDeviceCardEffect> {
            switch event {
            case .favoriteTapped:
                return .init(state: state, effects: [.toggleFavorite])
            }
        }
    }

    private(set) var state: DashboardDeviceCardState = .initial

    private let favoriteType: FavoriteType
    private let toggleFavorite: ToggleDashboardFavoriteEffectExecutor

    init(
        favoriteType: FavoriteType,
        toggleFavorite: ToggleDashboardFavoriteEffectExecutor
    ) {
        self.favoriteType = favoriteType
        self.toggleFavorite = toggleFavorite
    }

    func start() {}

    func send(_ event: DashboardDeviceCardEvent) {
        let transition = StateMachine.reduce(state, event, favoriteType: favoriteType)
        state = transition.state

        for effect in transition.effects {
            switch effect {
            case .toggleFavorite:
                launchFireAndForgetTask { [favoriteType, toggleFavorite] in
                    await toggleFavorite(favoriteType)
                }
            }
        }
    }
}
