import Foundation
import Observation

@Observable
@MainActor
final class TemperatureStore {
    struct Dependencies {
        let observeTemperature: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            observeTemperature: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.observeTemperature = observeTemperature
        }
    }

    private(set) var descriptor: TemperatureDescriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        uniqueId: String,
        initialDevice: DeviceRecord?,
        dependencies: Dependencies
    ) {
        self.descriptor = initialDevice?.temperatureDescriptor()
        self.worker = Worker(
            uniqueId: uniqueId,
            observeTemperature: dependencies.observeTemperature
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
    }

    private func applyIncomingDescriptor(_ descriptor: TemperatureDescriptor?) {
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private actor Worker {
        private let uniqueId: String
        private let observeTemperature: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            uniqueId: String,
            observeTemperature: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.uniqueId = uniqueId
            self.observeTemperature = observeTemperature
        }

        func observe(
            onDescriptor: @escaping @Sendable (TemperatureDescriptor?) async -> Void
        ) async {
            let stream = await observeTemperature(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                if let device, device.uniqueId != uniqueId {
                    continue
                }
                await onDescriptor(device?.temperatureDescriptor())
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
