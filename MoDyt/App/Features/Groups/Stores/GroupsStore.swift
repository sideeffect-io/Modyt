import Foundation
import Observation

struct GroupsState: Sendable, Equatable {
    var groups: [Group]

    static let initial = GroupsState(groups: [])
}

enum GroupsEvent: Sendable {
    case onAppear
    case groupsUpdated([Group])
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
        var state: GroupsState = .initial

        mutating func reduce(_ event: GroupsEvent) -> [GroupsEffect] {
            switch event {
            case .onAppear:
                return [.startObservingGroups]

            case .groupsUpdated(let groups):
                state.groups = groups
                return []

            case .refreshRequested:
                return [.refreshAll]

            case .toggleFavorite(let uniqueId):
                return [.toggleFavorite(uniqueId)]
            }
        }
    }

    struct Dependencies {
        let observeGroups: @Sendable () async -> any AsyncSequence<[Group], Never> & Sendable
        let toggleFavorite: @Sendable (String) async -> Void
        let refreshAll: @Sendable () async -> Void
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: GroupsState {
        stateMachine.state
    }

    private let groupsTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    init(dependencies: Dependencies) {
        self.worker = Worker(
            observeGroups: dependencies.observeGroups,
            toggleFavorite: dependencies.toggleFavorite,
            refreshAll: dependencies.refreshAll
        )
    }

    func send(_ event: GroupsEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    deinit {
        groupsTask.cancel()
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
        private let observeGroupsSource: @Sendable () async -> any AsyncSequence<[Group], Never> & Sendable
        private let toggleFavoriteAction: @Sendable (String) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeGroups: @escaping @Sendable () async -> any AsyncSequence<[Group], Never> & Sendable,
            toggleFavorite: @escaping @Sendable (String) async -> Void,
            refreshAll: @escaping @Sendable () async -> Void
        ) {
            self.observeGroupsSource = observeGroups
            self.toggleFavoriteAction = toggleFavorite
            self.refreshAllAction = refreshAll
        }

        func observeGroups(
            onUpdate: @escaping @Sendable ([Group]) async -> Void
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
