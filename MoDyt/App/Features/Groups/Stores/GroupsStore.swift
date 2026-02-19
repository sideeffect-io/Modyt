import Foundation
import Observation

struct GroupsState: Sendable, Equatable {
    var groups: [GroupRecord]

    static let initial = GroupsState(groups: [])
}

enum GroupsEvent: Sendable {
    case onAppear
    case groupsUpdated([GroupRecord])
    case refreshRequested
    case toggleFavorite(String)
}

enum GroupsEffect: Sendable, Equatable {
    case startObservingGroups
    case refreshAll
    case toggleFavorite(String)
}

enum GroupsReducer {
    static func reduce(state: GroupsState, event: GroupsEvent) -> (GroupsState, [GroupsEffect]) {
        var state = state
        var effects: [GroupsEffect] = []

        switch event {
        case .onAppear:
            effects = [.startObservingGroups]

        case .groupsUpdated(let groups):
            state.groups = groups

        case .refreshRequested:
            effects = [.refreshAll]

        case .toggleFavorite(let uniqueId):
            effects = [.toggleFavorite(uniqueId)]
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class GroupsStore {
    struct Dependencies {
        let observeGroups: @Sendable () async -> AsyncStream<[GroupRecord]>
        let toggleFavorite: @Sendable (String) async -> Void
        let refreshAll: @Sendable () async -> Void
    }

    private(set) var state: GroupsState

    private let groupsTask = TaskHandle()
    private let worker: Worker

    init(dependencies: Dependencies) {
        self.state = .initial
        self.worker = Worker(
            observeGroups: dependencies.observeGroups,
            toggleFavorite: dependencies.toggleFavorite,
            refreshAll: dependencies.refreshAll
        )
    }

    func send(_ event: GroupsEvent) {
        let (nextState, effects) = GroupsReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [GroupsEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: GroupsEffect) {
        switch effect {
        case .startObservingGroups:
            guard groupsTask.task == nil else { return }
            let taskHandle = groupsTask
            groupsTask.task = Task { [weak self, worker, weak taskHandle] in
                defer {
                    Task { @MainActor [weak taskHandle] in
                        taskHandle?.task = nil
                    }
                }
                await worker.observeGroups { [weak self] groups in
                    await self?.send(.groupsUpdated(groups))
                }
            }

        case .toggleFavorite(let uniqueId):
            Task { [worker] in
                await worker.toggleFavorite(uniqueId)
            }

        case .refreshAll:
            Task { [worker] in
                await worker.refreshAll()
            }
        }
    }

    private actor Worker {
        private let observeGroupsSource: @Sendable () async -> AsyncStream<[GroupRecord]>
        private let toggleFavoriteAction: @Sendable (String) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeGroups: @escaping @Sendable () async -> AsyncStream<[GroupRecord]>,
            toggleFavorite: @escaping @Sendable (String) async -> Void,
            refreshAll: @escaping @Sendable () async -> Void
        ) {
            self.observeGroupsSource = observeGroups
            self.toggleFavoriteAction = toggleFavorite
            self.refreshAllAction = refreshAll
        }

        func observeGroups(
            onUpdate: @escaping @Sendable ([GroupRecord]) async -> Void
        ) async {
            let stream = await observeGroupsSource()
            for await groups in stream {
                guard !Task.isCancelled else { return }
                let sorted = groups
                    .filter(\.isGroupUser)
                    .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                await onUpdate(sorted)
            }
        }

        func toggleFavorite(_ uniqueId: String) async {
            await toggleFavoriteAction(uniqueId)
        }

        func refreshAll() async {
            await refreshAllAction()
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
