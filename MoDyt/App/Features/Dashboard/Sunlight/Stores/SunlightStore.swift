import Foundation
import Observation

@Observable
@MainActor
final class SunlightStore {
    struct Dependencies {
        let observeSunlight: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            observeSunlight: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.observeSunlight = observeSunlight
        }
    }

    private(set) var descriptor: SunlightDescriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        uniqueId: String,
        initialDevice: DeviceRecord? = nil,
        dependencies: Dependencies
    ) {
        self.descriptor = initialDevice?.sunlightDescriptor()
        self.worker = Worker(
            uniqueId: uniqueId,
            observeSunlight: dependencies.observeSunlight
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
    }

    private func applyIncomingDescriptor(_ descriptor: SunlightDescriptor?) {
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private actor Worker {
        private let uniqueId: String
        private let observeSunlight: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            uniqueId: String,
            observeSunlight: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.uniqueId = uniqueId
            self.observeSunlight = observeSunlight
        }

        func observe(
            onDescriptor: @escaping @Sendable (SunlightDescriptor?) async -> Void
        ) async {
            let stream = await observeSunlight(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                if let device, device.uniqueId != uniqueId {
                    continue
                }
                await onDescriptor(device?.sunlightDescriptor())
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
