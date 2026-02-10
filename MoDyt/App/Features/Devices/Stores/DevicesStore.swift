import Foundation
import Observation

struct DeviceGroupSection: Sendable, Equatable, Identifiable {
    let group: DeviceGroup
    let devices: [DeviceRecord]

    var id: DeviceGroup { group }
}

struct DevicesState: Sendable, Equatable {
    var groupedDevices: [DeviceGroupSection]

    static let initial = DevicesState(groupedDevices: [])
}

enum DevicesEvent: Sendable {
    case onAppear
    case devicesUpdated([DeviceGroupSection])
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
        let observeDevices: @Sendable () async -> AsyncStream<[DeviceRecord]>
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
            deviceTask.task = Task { [weak self, worker] in
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
        private let observeDevicesSource: @Sendable () async -> AsyncStream<[DeviceRecord]>
        private let toggleFavoriteAction: @Sendable (String) async -> Void
        private let refreshAllAction: @Sendable () async -> Void

        init(
            observeDevices: @escaping @Sendable () async -> AsyncStream<[DeviceRecord]>,
            toggleFavorite: @escaping @Sendable (String) async -> Void,
            refreshAll: @escaping @Sendable () async -> Void
        ) {
            self.observeDevicesSource = observeDevices
            self.toggleFavoriteAction = toggleFavorite
            self.refreshAllAction = refreshAll
        }

        func observeDevices(
            onUpdate: @escaping @Sendable ([DeviceGroupSection]) async -> Void
        ) async {
            let stream = await observeDevicesSource()
            for await devices in stream {
                guard !Task.isCancelled else { return }
                await onUpdate(deriveGroupedDevices(from: devices))
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

private func deriveGroupedDevices(from devices: [DeviceRecord]) -> [DeviceGroupSection] {
    let grouped = Dictionary(grouping: devices, by: { $0.group })
    return DeviceGroup.allCases.compactMap { group -> DeviceGroupSection? in
        guard let sectionDevices = grouped[group] else { return nil }
        let sorted = sectionDevices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return DeviceGroupSection(group: group, devices: sorted)
    }
}
