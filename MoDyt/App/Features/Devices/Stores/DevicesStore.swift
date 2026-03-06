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
    case toggleFavorite(DeviceIdentifier)
}

enum DevicesEffect: Sendable, Equatable {
    case startObservingDevices
    case refreshAll
    case toggleFavorite(DeviceIdentifier)
}

@Observable
@MainActor
final class DevicesStore: StartableStore {
    struct StateMachine {
        var state: DevicesState = .initial

        mutating func reduce(_ event: DevicesEvent) -> [DevicesEffect] {
            switch event {
            case .onAppear:
                return [.startObservingDevices]

            case .devicesUpdated(let groupedDevices):
                state.groupedDevices = groupedDevices
                return []

            case .refreshRequested:
                return [.refreshAll]

            case .toggleFavorite(let uniqueId):
                return [.toggleFavorite(uniqueId)]
            }
        }
    }

    struct Dependencies {
        let observeDevices: @Sendable () async -> any AsyncSequence<[RepositoryDeviceTypeSection], Never> & Sendable
        let toggleFavorite: @Sendable (DeviceIdentifier) async -> Void
        let refreshAll: @Sendable () async -> Void
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: DevicesState {
        stateMachine.state
    }

    private let deviceTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    init(dependencies: Dependencies) {
        self.worker = Worker(
            observeDevices: dependencies.observeDevices,
            toggleFavorite: dependencies.toggleFavorite,
            refreshAll: dependencies.refreshAll
        )
    }

    func send(_ event: DevicesEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    deinit {
        deviceTask.cancel()
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
        private let toggleFavoriteAction: @Sendable (DeviceIdentifier) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeDevices: @escaping @Sendable () async -> any AsyncSequence<[RepositoryDeviceTypeSection], Never> & Sendable,
            toggleFavorite: @escaping @Sendable (DeviceIdentifier) async -> Void,
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

        func toggleFavorite(_ identifier: DeviceIdentifier) async {
            await toggleFavoriteAction(identifier)
        }

        func refreshAll() async {
            await refreshAllAction()
        }
    }
}
