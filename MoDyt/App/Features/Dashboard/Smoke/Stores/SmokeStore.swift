import Foundation
import Observation

@Observable
@MainActor
final class SmokeStore: StartableStore {
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
        self.worker = Worker(
            observeSmoke: dependencies.observeSmoke
        )
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        observationTask.task = Task { [weak self, worker] in
            guard let self else { return }
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
        private let observeSmoke: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

        init(
            observeSmoke: @escaping @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable
        ) {
            self.observeSmoke = observeSmoke
        }

        func observe(
            identifier: DeviceIdentifier,
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
