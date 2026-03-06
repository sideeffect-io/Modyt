import Foundation
import Observation

@Observable
@MainActor
final class EnergyConsumptionStore: StartableStore {
    struct State: Sendable, Equatable {
        var descriptor: Descriptor?
    }

    enum Event: Sendable {
        case descriptorWasReceived(Descriptor?)
    }

    enum Effect: Sendable, Equatable {}

    struct StateMachine {
        var state = State(descriptor: nil)

        mutating func reduce(_ event: Event) -> [Effect] {
            switch event {
            case .descriptorWasReceived(let descriptor):
                if state.descriptor != descriptor {
                    state.descriptor = descriptor
                }
            }
            return []
        }
    }

    struct Descriptor: Sendable, Equatable {
        let key: String
        let value: Double
        let range: ClosedRange<Double>
        let unitSymbol: String

        var clampedValue: Double {
            min(max(value, range.lowerBound), range.upperBound)
        }

        var normalizedValue: Double {
            let span = range.upperBound - range.lowerBound
            guard span > 0 else { return 0 }
            return (clampedValue - range.lowerBound) / span
        }
    }

    struct Dependencies {
        let observeEnergyConsumption: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeEnergyConsumption: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeEnergyConsumption = observeEnergyConsumption
        }
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var descriptor: Descriptor? {
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
            observeEnergyConsumption: dependencies.observeEnergyConsumption
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let identifier = self.identifier
        observationTask.task = Task { [weak self, worker] in
            await worker.observe(identifier: identifier) { [weak self] descriptor in
                await self?.send(.descriptorWasReceived(descriptor))
            }
        }
    }

    deinit {
        observationTask.cancel()
    }

    func send(_ event: Event) {
        _ = stateMachine.reduce(event)
    }

    private actor Worker {
        private let observeEnergyConsumption: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeEnergyConsumption: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeEnergyConsumption = observeEnergyConsumption
        }

        func observe(
            identifier: DeviceIdentifier,
            onDescriptor: @escaping @Sendable (Descriptor?) async -> Void
        ) async {
            let stream = await observeEnergyConsumption(identifier)
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onDescriptor(device?.energyConsumptionDescriptor())
            }
        }
    }
}
