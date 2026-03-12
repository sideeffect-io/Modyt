import Foundation
import Observation

struct GroupsState: Sendable, Equatable {
    var groups: [Group]

    static let initial = GroupsState(groups: [])
}

enum GroupsEvent: Sendable {
    case onAppear
    case groupsObserved([Group])
    case refreshRequested
    case toggleFavorite(String)
}

enum GroupsEffect: Sendable, Equatable {
    case startObservingGroups
    case refreshAll
    case toggleFavorite(String)
}

@Observable
@MainActor
final class GroupsStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: GroupsState,
            _ event: GroupsEvent
        ) -> Transition<GroupsState, GroupsEffect> {
            var state = state

            switch event {
            case .onAppear:
                return .init(state: state, effects: [.startObservingGroups])

            case .groupsObserved(let groups):
                state.groups = GroupsStoreProjector.groups(from: groups)
                return .init(state: state)

            case .refreshRequested:
                return .init(state: state, effects: [.refreshAll])

            case .toggleFavorite(let uniqueId):
                return .init(state: state, effects: [.toggleFavorite(uniqueId)])
            }
        }
    }

    private(set) var state: GroupsState = .initial

    private let observeGroups: ObserveGroupsEffectExecutor
    private let toggleFavorite: ToggleGroupFavoriteEffectExecutor
    private let refreshAll: RefreshGroupsEffectExecutor
    private var groupsTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        observeGroups: ObserveGroupsEffectExecutor,
        toggleFavorite: ToggleGroupFavoriteEffectExecutor,
        refreshAll: RefreshGroupsEffectExecutor
    ) {
        self.observeGroups = observeGroups
        self.toggleFavorite = toggleFavorite
        self.refreshAll = refreshAll
    }

    func send(_ event: GroupsEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    isolated deinit {
        groupsTask?.cancel()
    }

    private func handle(_ effects: [GroupsEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: GroupsEffect) {
        switch effect {
        case .startObservingGroups:
            guard groupsTask == nil else { return }
            replaceTask(
                &groupsTask,
                with: makeTrackedStreamTask(
                    operation: { [observeGroups] in
                        await observeGroups()
                    },
                    onEvent: { [weak self] event in
                        self?.send(event)
                    },
                    onFinish: { [weak self] in
                        self?.groupsTask = nil
                    }
                )
            )

        case .toggleFavorite(let uniqueId):
            launchFireAndForgetTask { [toggleFavorite] in
                await toggleFavorite(uniqueId)
            }

        case .refreshAll:
            launchFireAndForgetTask { [refreshAll] in
                await refreshAll()
            }
        }
    }
}

private enum GroupsStoreProjector {
    nonisolated static func groups(from groups: [Group]) -> [Group] {
        groups
            .filter(\.isGroupUser)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }
}
