import Foundation
import Observation
import DeltaDoreClient

struct DashboardDeviceCardState: Sendable, Equatable {
    let uniqueId: String
    var device: DeviceRecord?
}

enum DashboardDeviceCardEvent: Sendable {
    case onAppear
    case deviceUpdated(DeviceRecord?)
    case controlChanged(key: String, value: JSONValue)
}

enum DashboardDeviceCardEffect: Sendable, Equatable {
    case startObservingDevice
    case applyOptimisticUpdate(uniqueId: String, key: String, value: JSONValue)
    case sendDeviceCommand(uniqueId: String, key: String, value: JSONValue)
}

enum DashboardDeviceCardReducer {
    static func reduce(
        state: DashboardDeviceCardState,
        event: DashboardDeviceCardEvent
    ) -> (DashboardDeviceCardState, [DashboardDeviceCardEffect]) {
        var state = state
        var effects: [DashboardDeviceCardEffect] = []

        switch event {
        case .onAppear:
            effects = [.startObservingDevice]

        case .deviceUpdated(let device):
            state.device = device

        case .controlChanged(let key, let value):
            guard let device = state.device else { return (state, effects) }

            let isShutterSliderControl = device.group == .shutter
                && device.primaryControlDescriptor()?.kind == .slider
                && device.primaryControlDescriptor()?.key == key

            if isShutterSliderControl {
                effects = [.sendDeviceCommand(uniqueId: state.uniqueId, key: key, value: value)]
            } else {
                effects = [
                    .applyOptimisticUpdate(uniqueId: state.uniqueId, key: key, value: value),
                    .sendDeviceCommand(uniqueId: state.uniqueId, key: key, value: value)
                ]
            }
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class DashboardDeviceCardStore {
    struct Dependencies {
        let observeDevice: (String) async -> AsyncStream<DeviceRecord?>
        let applyOptimisticUpdate: (String, String, JSONValue) async -> Void
        let sendDeviceCommand: (String, String, JSONValue) async -> Void
    }

    private(set) var state: DashboardDeviceCardState

    private let dependencies: Dependencies
    private let deviceTask = TaskHandle()

    init(uniqueId: String, dependencies: Dependencies) {
        self.state = DashboardDeviceCardState(uniqueId: uniqueId, device: nil)
        self.dependencies = dependencies
    }

    func send(_ event: DashboardDeviceCardEvent) {
        let (nextState, effects) = DashboardDeviceCardReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [DashboardDeviceCardEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: DashboardDeviceCardEffect) {
        switch effect {
        case .startObservingDevice:
            guard deviceTask.task == nil else { return }
            let uniqueId = state.uniqueId
            deviceTask.task = Task { [weak self, dependencies] in
                let stream = await dependencies.observeDevice(uniqueId)
                for await device in stream {
                    self?.send(.deviceUpdated(device))
                }
            }

        case .applyOptimisticUpdate(let uniqueId, let key, let value):
            Task { [dependencies] in
                await dependencies.applyOptimisticUpdate(uniqueId, key, value)
            }

        case .sendDeviceCommand(let uniqueId, let key, let value):
            Task { [dependencies] in
                await dependencies.sendDeviceCommand(uniqueId, key, value)
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
