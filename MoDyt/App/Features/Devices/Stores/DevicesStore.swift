import Foundation
import Observation

struct DevicesState: Sendable, Equatable {
    var groupedDevices: [RepositoryDeviceTypeSection]

    static let initial = DevicesState(groupedDevices: [])
}

enum DevicesEvent: Sendable {
    case onAppear
    case devicesUpdated([RepositoryDeviceTypeSection])
    case refreshRequested
    case toggleFavorite(String)
}

enum DevicesEffect: Sendable, Equatable {
    case startObservingDevices
    case refreshAll
    case toggleFavorite(String)
}

enum DevicesReducer {
    static func reduce(state: DevicesState, event: DevicesEvent) -> (DevicesState, [DevicesEffect]) {
        var state = state
        var effects: [DevicesEffect] = []

        switch event {
        case .onAppear:
            effects = [.startObservingDevices]

        case .devicesUpdated(let groupedDevices):
            state.groupedDevices = groupedDevices

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
final class DevicesStore {
    struct Dependencies {
        let observeDevices: @Sendable () async -> any AsyncSequence<[RepositoryDeviceTypeSection], Never> & Sendable
        let toggleFavorite: @Sendable (String) async -> Void
        let refreshAll: @Sendable () async -> Void
    }

    private(set) var state: DevicesState

    private let deviceTask = TaskHandle()
    private let worker: Worker

    init(dependencies: Dependencies) {
        self.state = .initial
        self.worker = Worker(
            observeDevices: dependencies.observeDevices,
            toggleFavorite: dependencies.toggleFavorite,
            refreshAll: dependencies.refreshAll
        )
    }

    func send(_ event: DevicesEvent) {
        let (nextState, effects) = DevicesReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [DevicesEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: DevicesEffect) {
        switch effect {
        case .startObservingDevices:
            guard deviceTask.task == nil else { return }
            let taskHandle = deviceTask
            deviceTask.task = Task { [weak self, worker, weak taskHandle] in
                defer {
                    Task { @MainActor [weak taskHandle] in
                        taskHandle?.task = nil
                    }
                }
                await worker.observeDevices { [weak self] groupedDevices in
                    await self?.send(.devicesUpdated(groupedDevices))
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
        private let observeDevicesSource: @Sendable () async -> any AsyncSequence<[RepositoryDeviceTypeSection], Never> & Sendable
        private let toggleFavoriteAction: @Sendable (String) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeDevices: @escaping @Sendable () async -> any AsyncSequence<[RepositoryDeviceTypeSection], Never> & Sendable,
            toggleFavorite: @escaping @Sendable (String) async -> Void,
            refreshAll: @escaping @Sendable () async -> Void
        ) {
            self.observeDevicesSource = observeDevices
            self.toggleFavoriteAction = toggleFavorite
            self.refreshAllAction = refreshAll
        }

        func observeDevices(
            onUpdate: @escaping @Sendable ([RepositoryDeviceTypeSection]) async -> Void
        ) async {
            let stream = await observeDevicesSource()
            for await groupedDevices in stream {
                guard !Task.isCancelled else { return }
                await onUpdate(groupedDevices)
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
