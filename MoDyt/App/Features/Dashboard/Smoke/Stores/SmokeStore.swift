import Foundation
import Observation

@Observable
@MainActor
final class SmokeStore: StartableStore {
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

            var hasBatteryIssue: Bool {
                batteryDefect == true
            }

            var normalizedBatteryLevel: Double? {
                guard let batteryLevel else { return nil }
                return min(max(batteryLevel, 0), 100)
            }
        }

        let smokeKey: String
        let smokeDetected: Bool
        let batteryStatus: BatteryStatus?

        var batteryDefect: Bool? {
            batteryStatus?.batteryDefect
        }

        var hasBatteryIssue: Bool {
            batteryStatus?.hasBatteryIssue == true
        }

        var normalizedBatteryLevel: Double? {
            batteryStatus?.normalizedBatteryLevel
        }
    }

    private(set) var state = State(descriptor: nil)

    var descriptor: Descriptor? {
        state.descriptor
    }

    private let observeSmoke: ObserveSmokeEffectExecutor
    private var observationTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        observeSmoke: ObserveSmokeEffectExecutor
    ) {
        self.observeSmoke = observeSmoke
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
                        operation: { [observeSmoke] in
                            await observeSmoke()
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
        .descriptorWasReceived(device?.smokeStoreDescriptor())
    }
}
