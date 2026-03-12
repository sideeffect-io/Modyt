import Foundation
import Observation

struct DevicesState: Sendable, Equatable {
    var groupedDevices: [DeviceTypeSection]

    static let initial = DevicesState(groupedDevices: [])
}

enum DevicesEvent: Sendable {
    case onAppear
    case devicesObserved([Device])
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
        static func reduce(
            _ state: DevicesState,
            _ event: DevicesEvent
        ) -> Transition<DevicesState, DevicesEffect> {
            var state = state

            switch event {
            case .onAppear:
                return .init(state: state, effects: [.startObservingDevices])

            case .devicesObserved(let devices):
                state.groupedDevices = DeviceListProjector.sections(from: devices)
                return .init(state: state)

            case .refreshRequested:
                return .init(state: state, effects: [.refreshAll])

            case .toggleFavorite(let uniqueId):
                return .init(state: state, effects: [.toggleFavorite(uniqueId)])
            }
        }
    }

    private(set) var state: DevicesState = .initial

    private let observeDevices: ObserveDevicesEffectExecutor
    private let toggleFavorite: ToggleDeviceFavoriteEffectExecutor
    private let refreshAll: RefreshDevicesEffectExecutor
    private var deviceTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        observeDevices: ObserveDevicesEffectExecutor,
        toggleFavorite: ToggleDeviceFavoriteEffectExecutor,
        refreshAll: RefreshDevicesEffectExecutor
    ) {
        self.observeDevices = observeDevices
        self.toggleFavorite = toggleFavorite
        self.refreshAll = refreshAll
    }

    func send(_ event: DevicesEvent) {
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
        deviceTask?.cancel()
    }

    private func handle(_ effects: [DevicesEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: DevicesEffect) {
        switch effect {
        case .startObservingDevices:
            guard deviceTask == nil else { return }
            replaceTask(
                &deviceTask,
                with: makeTrackedStreamTask(
                    operation: { [observeDevices] in
                        await observeDevices()
                    },
                    onEvent: { [weak self] event in
                        self?.send(event)
                    },
                    onFinish: { [weak self] in
                        self?.deviceTask = nil
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
