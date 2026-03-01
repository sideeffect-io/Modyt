import Foundation
import Observation

@Observable
@MainActor
final class SmokeStore {
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

    struct Dependencies {
        let observeSmoke: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeSmoke: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeSmoke = observeSmoke
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
            observeSmoke: dependencies.observeSmoke
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
        private let observeSmoke: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            identifier: DeviceIdentifier,
            observeSmoke: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.identifier = identifier
            self.observeSmoke = observeSmoke
        }

        func observe(
            onDescriptor: @escaping @Sendable (Descriptor?) async -> Void
        ) async {
            let stream = await observeSmoke(identifier)
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onDescriptor(device?.smokeStoreDescriptor())
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
