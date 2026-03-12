import Foundation
import Observation

@Observable
@MainActor
final class ThermostatStore: StartableStore {
    struct State: Sendable, Equatable {
        var descriptor: Descriptor?
    }

    enum Event: Sendable {
        case onAppear
        case descriptorWasResolved(Descriptor?)
    }

    enum Effect: Sendable, Equatable {
        case startObserving
    }

    struct StateMachine {
        static func reduce(
            _ state: State,
            _ event: Event
        ) -> Transition<State, Effect> {
            var state = state

            switch event {
            case .onAppear:
                return .init(state: state, effects: [.startObserving])

            case .descriptorWasResolved(let descriptor):
                if state.descriptor != descriptor {
                    state.descriptor = descriptor
                }
            }
            return .init(state: state)
        }
    }

    struct Descriptor: Sendable, Equatable {
        struct Temperature: Sendable, Equatable {
            let value: Double
            let unitSymbol: String?
        }

        struct Humidity: Sendable, Equatable {
            let value: Double
            let unitSymbol: String?
        }

        let temperature: Temperature?
        let setpoint: Temperature?
        let humidity: Humidity?
    }

    private(set) var storeState = State(descriptor: nil)

    var state: Descriptor? {
        storeState.descriptor
    }

    private let observeThermostat: ObserveThermostatEffectExecutor
    private var observationTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        observeThermostat: ObserveThermostatEffectExecutor
    ) {
        self.observeThermostat = observeThermostat
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.onAppear)
    }

    isolated deinit {
        observationTask?.cancel()
    }

    func send(_ event: Event) {
        let transition = StateMachine.reduce(storeState, event)
        storeState = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [Effect]) {
        for effect in effects {
            switch effect {
            case .startObserving:
                guard observationTask == nil else { return }
                replaceTask(
                    &observationTask,
                    with: makeTrackedStreamTask(
                        operation: { [observeThermostat] in
                            await observeThermostat()
                        },
                        onEvent: { [weak self] event in
                            self?.send(event)
                        },
                        onFinish: { [weak self] in
                            self?.observationTask = nil
                        }
                    )
                )
            }
        }
    }

    nonisolated static func observationEvent(from device: Device?) -> Event? {
        guard let device else {
            return .descriptorWasResolved(nil)
        }

        guard let descriptor = device.thermostatDescriptor() else {
            if isClimateCandidate(device) == false {
                return .descriptorWasResolved(nil)
            }
            return nil
        }

        return .descriptorWasResolved(descriptor)
    }

    private nonisolated static func isClimateCandidate(_ device: Device) -> Bool {
        switch device.controlKind {
        case .thermostat, .heatPump, .temperature:
            return true
        default:
            return device.hasLikelyClimatePayload
        }
    }
}
