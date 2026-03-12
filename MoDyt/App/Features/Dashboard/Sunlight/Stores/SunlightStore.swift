import Foundation
import Observation

@Observable
@MainActor
final class SunlightStore: StartableStore {
    struct State: Sendable, Equatable {
        var descriptor: Descriptor?
    }

    enum Event: Sendable {
        case onAppear
        case descriptorWasReceived(Descriptor?)
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

            case .descriptorWasReceived(let descriptor):
                if state.descriptor != descriptor {
                    state.descriptor = descriptor
                }
            }
            return .init(state: state)
        }
    }

    struct Descriptor: Sendable, Equatable {
        struct BatteryStatus: Sendable, Equatable {
            let batteryDefectKey: String?
            let batteryDefect: Bool?
            let batteryLevelKey: String?
            let batteryLevel: Double?

            var normalizedBatteryLevel: Double? {
                guard let batteryLevel else { return nil }
                return min(max(batteryLevel, 0), 100)
            }
        }

        let key: String
        let value: Double
        let range: ClosedRange<Double>
        let unitSymbol: String
        let batteryStatus: BatteryStatus?

        var clampedValue: Double {
            min(max(value, range.lowerBound), range.upperBound)
        }

        var normalizedValue: Double {
            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return 0 }
            return (clampedValue - range.lowerBound) / span
        }
    }

    private(set) var state = State(descriptor: nil)

    var descriptor: Descriptor? {
        state.descriptor
    }

    private let observeSunlight: ObserveSunlightEffectExecutor
    private var observationTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        observeSunlight: ObserveSunlightEffectExecutor
    ) {
        self.observeSunlight = observeSunlight
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
        let transition = StateMachine.reduce(state, event)
        state = transition.state
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
                        operation: { [observeSunlight] in
                            await observeSunlight()
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
        .descriptorWasReceived(device?.sunlightStoreDescriptor())
    }
}
