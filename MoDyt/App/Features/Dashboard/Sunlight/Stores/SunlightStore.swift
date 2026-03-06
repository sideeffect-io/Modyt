import Foundation
import Observation

@Observable
@MainActor
final class SunlightStore: StartableStore {
    struct State: Sendable, Equatable {
        var descriptor: Descriptor?
    }

    enum Event: Sendable {
        case descriptorWasReceived(Descriptor?)
    }

    enum Effect: Sendable, Equatable {}

    struct StateMachine {
        var state = State(descriptor: nil)

        mutating func reduce(_ event: Event) -> [Effect] {
            switch event {
            case .descriptorWasReceived(let descriptor):
                if state.descriptor != descriptor {
                    state.descriptor = descriptor
                }
            }
            return []
        }
    }

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
        let observeSunlight: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeSunlight: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeSunlight = observeSunlight
        }
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var descriptor: Descriptor? {
        stateMachine.state.descriptor
    }

    private let identifier: DeviceIdentifier
    private let observationTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    init(
        dependencies: Dependencies,
        identifier: DeviceIdentifier
    ) {
        self.identifier = identifier
        self.worker = Worker(observeSunlight: dependencies.observeSunlight)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        let identifier = self.identifier
        observationTask.task = Task { [weak self, worker] in
            await worker.observe(identifier: identifier) { [weak self] descriptor in
                await self?.send(.descriptorWasReceived(descriptor))
            }
        }
    }

    deinit {
        observationTask.cancel()
    }

    func send(_ event: Event) {
        _ = stateMachine.reduce(event)
    }

    private actor Worker {
        private let observeSunlight: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeSunlight: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeSunlight = observeSunlight
        }

        func observe(
            identifier: DeviceIdentifier,
            onDescriptor: @escaping @Sendable (Descriptor?) async -> Void
        ) async {
            let stream = await observeSunlight(identifier)
            for await device in stream {
                guard !Task.isCancelled else { return }
                await onDescriptor(device?.sunlightStoreDescriptor())
            }
        }
    }
}
