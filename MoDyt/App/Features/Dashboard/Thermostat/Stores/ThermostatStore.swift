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
        let setpoint: Temperature?
        let humidity: Humidity?
    }

    struct Dependencies {
        let observeThermostat: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeThermostat: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeThermostat = observeThermostat
        }
    }

    private(set) var state: Descriptor?

    private let observationTask = TaskHandle()
    private let worker: Worker

    init(
        identifier: DeviceIdentifier,
        dependencies: Dependencies
    ) {
        self.worker = Worker(
            identifier: identifier,
            observeThermostat: dependencies.observeThermostat
        )

        observationTask.task = Task { [weak self, worker] in
            await worker.observe { [weak self] device, state in
                await self?.applyIncomingObservation(device: device, state: state)
            }
        }
    }

    private func applyIncomingObservation(device: Device?, state: Descriptor?) {
        guard let device else {
            applyIncomingState(nil)
            return
        }

        guard let state else {
            if Self.isClimateCandidate(device) == false {
                applyIncomingState(nil)
            }
            return
        }

        applyIncomingState(state)
    }

    private func applyIncomingState(_ state: Descriptor?) {
        guard self.state != state else { return }
        self.state = state
    }

    private static func isClimateCandidate(_ device: Device) -> Bool {
        switch device.controlKind {
        case .thermostat, .heatPump, .temperature:
            return true
        default:
            return device.hasLikelyClimatePayload
        }
    }

    private actor Worker {
        private let identifier: DeviceIdentifier
        private let observeThermostat: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            identifier: DeviceIdentifier,
            observeThermostat: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.identifier = identifier
            self.observeThermostat = observeThermostat
        }

        func observe(
            onState: @escaping @Sendable (Device?, Descriptor?) async -> Void
        ) async {
            let stream = await observeThermostat(identifier)
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onState(device, device?.thermostatDescriptor())
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
