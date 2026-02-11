import Foundation
import Observation

@Observable
@MainActor
final class EnergyConsumptionStore {
    struct Dependencies {
        let observeEnergyConsumption: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            observeEnergyConsumption: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.observeEnergyConsumption = observeEnergyConsumption
        }
    }

    private(set) var descriptor: EnergyConsumptionDescriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        uniqueId: String,
        initialDevice: DeviceRecord? = nil,
        dependencies: Dependencies
    ) {
        self.descriptor = initialDevice?.energyConsumptionDescriptor()
        self.worker = Worker(
            uniqueId: uniqueId,
            observeEnergyConsumption: dependencies.observeEnergyConsumption
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
    }

    private func applyIncomingDescriptor(_ descriptor: EnergyConsumptionDescriptor?) {
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private actor Worker {
        private let uniqueId: String
        private let observeEnergyConsumption: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            uniqueId: String,
            observeEnergyConsumption: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.uniqueId = uniqueId
            self.observeEnergyConsumption = observeEnergyConsumption
        }

        func observe(
            onDescriptor: @escaping @Sendable (EnergyConsumptionDescriptor?) async -> Void
        ) async {
            let stream = await observeEnergyConsumption(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                if let device, device.uniqueId != uniqueId {
                    continue
                }
                await onDescriptor(device?.energyConsumptionDescriptor())
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
