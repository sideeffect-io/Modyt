import Foundation
import Observation

@Observable
@MainActor
final class ThermostatStore {
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
        let humidity: Humidity?
    }

    struct Dependencies {
        let observeThermostat: @Sendable (String) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeThermostat: @escaping @Sendable (String) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeThermostat = observeThermostat
        }
    }

    private(set) var state: Descriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        uniqueId: String,
        dependencies: Dependencies
    ) {
        self.worker = Worker(
            uniqueId: uniqueId,
            observeThermostat: dependencies.observeThermostat
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] state in
                await self?.applyIncomingState(state)
            }
        }
    }

    private func applyIncomingState(_ state: Descriptor?) {
        guard self.state != state else { return }
        self.state = state
    }

    private actor Worker {
        private let uniqueId: String
        private let observeThermostat: @Sendable (String) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            uniqueId: String,
            observeThermostat: @escaping @Sendable (String) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.uniqueId = uniqueId
            self.observeThermostat = observeThermostat
        }

        func observe(
            onState: @escaping @Sendable (Descriptor?) async -> Void
        ) async {
            let stream = await observeThermostat(uniqueId)
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onState(device?.thermostatDescriptor())
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
