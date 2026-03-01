import Foundation
import Observation

@Observable
@MainActor
final class EnergyConsumptionStore {
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

    private(set) var descriptor: Descriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        identifier: DeviceIdentifier,
        dependencies: Dependencies
    ) {
        self.descriptor = nil
        self.worker = Worker(
            identifier: identifier,
            observeEnergyConsumption: dependencies.observeEnergyConsumption
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
    }

    private func applyIncomingDescriptor(_ descriptor: Descriptor?) {
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private actor Worker {
        private let identifier: DeviceIdentifier
        private let observeEnergyConsumption: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            identifier: DeviceIdentifier,
            observeEnergyConsumption: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.identifier = identifier
            self.observeEnergyConsumption = observeEnergyConsumption
        }

        func observe(
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

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    deinit {
        task?.cancel()
    }
}
