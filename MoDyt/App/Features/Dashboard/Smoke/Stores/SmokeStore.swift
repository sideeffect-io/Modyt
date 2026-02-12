import Foundation
import Observation

@Observable
@MainActor
final class SmokeStore {
    struct Dependencies {
        let observeSmoke: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            observeSmoke: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.observeSmoke = observeSmoke
        }
    }

    private(set) var descriptor: SmokeDetectorDescriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        uniqueId: String,
        initialDevice: DeviceRecord? = nil,
        dependencies: Dependencies
    ) {
        self.descriptor = initialDevice?.smokeDetectorDescriptor()
        self.worker = Worker(
            uniqueId: uniqueId,
            observeSmoke: dependencies.observeSmoke
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] descriptor in
                await self?.applyIncomingDescriptor(descriptor)
            }
        }
    }

    private func applyIncomingDescriptor(_ descriptor: SmokeDetectorDescriptor?) {
        guard self.descriptor != descriptor else { return }
        self.descriptor = descriptor
    }

    private actor Worker {
        private let uniqueId: String
        private let observeSmoke: @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable

        init(
            uniqueId: String,
            observeSmoke: @escaping @Sendable (String) async -> any AsyncSequence<DeviceRecord?, Never> & Sendable
        ) {
            self.uniqueId = uniqueId
            self.observeSmoke = observeSmoke
        }

        func observe(
            onDescriptor: @escaping @Sendable (SmokeDetectorDescriptor?) async -> Void
        ) async {
            let stream = await observeSmoke(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                if let device, device.uniqueId != uniqueId {
                    continue
                }
                await onDescriptor(device?.smokeDetectorDescriptor())
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
