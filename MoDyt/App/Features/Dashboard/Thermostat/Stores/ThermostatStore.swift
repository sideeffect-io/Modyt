import Foundation
import Observation

@Observable
@MainActor
final class ThermostatStore: StartableStore {
    struct State: Sendable, Equatable {
        var descriptor: Descriptor?
    }

    enum Event: Sendable {
        case descriptorWasResolved(Descriptor?)
    }

    enum Effect: Sendable, Equatable {}

    struct StateMachine {
        var state = State(descriptor: nil)

        mutating func reduce(_ event: Event) -> [Effect] {
            switch event {
            case .descriptorWasResolved(let descriptor):
                if state.descriptor != descriptor {
                    state.descriptor = descriptor
                }
            }
            return []
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

    struct Dependencies {
        let observeThermostat: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeThermostat: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeThermostat = observeThermostat
        }
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: Descriptor? {
        stateMachine.state.descriptor
    }

    private let identifier: DeviceIdentifier
    private let observationTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    init(
        dependencies: Dependencies,
        identifier: DeviceIdentifier
    ) {
        self.identifier = identifier
        self.worker = Worker(
            observeThermostat: dependencies.observeThermostat
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let identifier = self.identifier
        observationTask.task = Task { [weak self, worker] in
            await worker.observe(identifier: identifier) { [weak self] device, state in
                await self?.applyIncomingObservation(device: device, state: state)
            }
        }
    }

    deinit {
        observationTask.cancel()
    }

    private func applyIncomingObservation(device: Device?, state: Descriptor?) {
        guard let device else {
            send(.descriptorWasResolved(nil))
            return
        }

        guard let state else {
            if Self.isClimateCandidate(device) == false {
                send(.descriptorWasResolved(nil))
            }
            return
        }

        send(.descriptorWasResolved(state))
    }

    func send(_ event: Event) {
        _ = stateMachine.reduce(event)
    }

    private static func isClimateCandidate(_ device: Device) -> Bool {
        switch device.controlKind {
        case .thermostat, .heatPump, .temperature:
            return true
        default:
            return device.hasLikelyClimatePayload
        }
    }

    private actor Worker {
        private let observeThermostat: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeThermostat: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeThermostat = observeThermostat
        }

        func observe(
            identifier: DeviceIdentifier,
            onState: @escaping @Sendable (Device?, Descriptor?) async -> Void
        ) async {
            let stream = await observeThermostat(identifier)
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onState(device, device?.thermostatDescriptor())
            }
        }
    }
}
