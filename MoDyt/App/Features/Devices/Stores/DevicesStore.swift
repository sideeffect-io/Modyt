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
    case devicesUpdated([DeviceRecord])
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

        case .devicesUpdated(let devices):
            state.groupedDevices = deriveGroupedDevices(from: devices)

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
        let observeDevices: () async -> AsyncStream<[DeviceRecord]>
        let toggleFavorite: (String) async -> Void
        let refreshAll: () async -> Void
    }

    private(set) var state: DevicesState

    private let dependencies: Dependencies
    private let deviceTask = TaskHandle()

    init(dependencies: Dependencies) {
        self.state = .initial
        self.dependencies = dependencies
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
            deviceTask.task = Task { [weak self, dependencies] in
                let stream = await dependencies.observeDevices()
                for await devices in stream {
                    self?.send(.devicesUpdated(devices))
                }
            }

        case .toggleFavorite(let uniqueId):
            Task { [dependencies] in
                await dependencies.toggleFavorite(uniqueId)
            }

        case .refreshAll:
            Task { [dependencies] in
                await dependencies.refreshAll()
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

private func deriveGroupedDevices(from devices: [DeviceRecord]) -> [DeviceGroupSection] {
    let grouped = Dictionary(grouping: devices, by: { $0.group })
    return DeviceGroup.allCases.compactMap { group -> DeviceGroupSection? in
        guard let sectionDevices = grouped[group] else { return nil }
        let sorted = sectionDevices.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
        return DeviceGroupSection(group: group, devices: sorted)
    }
}
