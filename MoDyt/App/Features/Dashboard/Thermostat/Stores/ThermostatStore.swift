import Foundation
import Observation

@Observable
@MainActor
final class ThermostatStore {
    struct Dependencies {
        let observeThermostat: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            observeThermostat: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.observeThermostat = observeThermostat
        }
    }

    private(set) var descriptor: ThermostatDescriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        uniqueId: String,
        initialDevice: DeviceRecord? = nil,
        dependencies: Dependencies
    ) {
        self.descriptor = initialDevice?.thermostatDescriptor()
        self.worker = Worker(
            uniqueId: uniqueId,
            observeThermostat: dependencies.observeThermostat
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
    }

    private func applyIncomingDescriptor(_ descriptor: ThermostatDescriptor?) {
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private actor Worker {
        private let uniqueId: String
        private let observeThermostat: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            uniqueId: String,
            observeThermostat: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.uniqueId = uniqueId
            self.observeThermostat = observeThermostat
        }

        func observe(
            onDescriptor: @escaping @Sendable (ThermostatDescriptor?) async -> Void
        ) async {
            let stream = await observeThermostat(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                if let device, device.uniqueId != uniqueId {
                    continue
                }
                await onDescriptor(device?.thermostatDescriptor())
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
