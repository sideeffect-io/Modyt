import Foundation
import Observation

@Observable
@MainActor
final class SunlightStore {
    struct Descriptor: Sendable, Equatable {
        struct BatteryStatus: Sendable, Equatable {
            let batteryDefectKey: String?
            let batteryDefect: Bool?
            let batteryLevelKey: String?
            let batteryLevel: Double?

            var normalizedBatteryLevel: Double? {
                guard let batteryLevel else { return nil }
                return min(max(batteryLevel, 0), 100)
            }
        }

        let key: String
        let value: Double
        let range: ClosedRange<Double>
        let unitSymbol: String
        let batteryStatus: BatteryStatus?

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
        let observeSunlight: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeSunlight: @escaping @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeSunlight = observeSunlight
        }
    }

    private(set) var descriptor: Descriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        initialDescriptor: Descriptor? = nil,
        dependencies: Dependencies
    ) {
        self.descriptor = initialDescriptor
        self.worker = Worker(observeSunlight: dependencies.observeSunlight)

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
        private let observeSunlight: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeSunlight: @escaping @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeSunlight = observeSunlight
        }

        func observe(
            onDescriptor: @escaping @Sendable (Descriptor?) async -> Void
        ) async {
            let stream = await observeSunlight()
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onDescriptor(device?.sunlightStoreDescriptor())
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
