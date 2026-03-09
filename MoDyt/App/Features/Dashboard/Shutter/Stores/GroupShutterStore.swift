import Foundation
import Observation

enum GroupShutterState: Sendable, Equatable {
    case featureIsIdle(deviceIds: [DeviceIdentifier])

    var deviceIds: [DeviceIdentifier] {
        switch self {
        case .featureIsIdle(let deviceIds):
            return deviceIds
        }
    }
}

enum GroupShutterEvent: Sendable, Equatable {
    case targetWasSetInApp(target: Int)
}

enum GroupShutterEffect: Sendable, Equatable {
    case sendCommand(deviceIds: [DeviceIdentifier], position: Int)
    case persistTarget(deviceIds: [DeviceIdentifier], target: Int?)
}

@Observable
@MainActor
final class GroupShutterStore: StartableStore {
    struct StateMachine {
        var state: GroupShutterState = .featureIsIdle(deviceIds: [])

        mutating func reduce(_ event: GroupShutterEvent) -> [GroupShutterEffect] {
            switch (state, event) {
            case let (.featureIsIdle(deviceIds), .targetWasSetInApp(target)):
                guard deviceIds.isEmpty == false else { return [] }
                return [
                    .sendCommand(deviceIds: deviceIds, position: target),
                    .persistTarget(deviceIds: deviceIds, target: target),
                ]
            }
        }
    }

    struct Dependencies {
        let sendCommand: @Sendable ([DeviceIdentifier], Int) async -> Void
        let persistTarget: @Sendable ([DeviceIdentifier], Int?) async -> Void

        init(
            sendCommand: @escaping @Sendable ([DeviceIdentifier], Int) async -> Void,
            persistTarget: @escaping @Sendable ([DeviceIdentifier], Int?) async -> Void
        ) {
            self.sendCommand = sendCommand
            self.persistTarget = persistTarget
        }
    }

    private(set) var stateMachine: StateMachine

    var state: GroupShutterState {
        stateMachine.state
    }

    private let worker: Worker

    init(
        dependencies: Dependencies,
        deviceIds: [DeviceIdentifier]
    ) {
        self.stateMachine = StateMachine(
            state: .featureIsIdle(deviceIds: deviceIds.uniquePreservingOrder())
        )
        self.worker = Worker(
            sendCommand: dependencies.sendCommand,
            persistTarget: dependencies.persistTarget
        )
    }

    func start() {}

    func send(_ event: GroupShutterEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    private func handle(_ effects: [GroupShutterEffect]) {
        for effect in effects {
            switch effect {
            case .sendCommand(let deviceIds, let position):
                Task { [worker] in
                    await worker.sendCommand(deviceIds: deviceIds, position: position)
                }

            case .persistTarget(let deviceIds, let target):
                Task { [worker] in
                    await worker.persistTarget(deviceIds: deviceIds, target: target)
                }
            }
        }
    }

    private actor Worker {
        private let sendCommandAction: @Sendable ([DeviceIdentifier], Int) async -> Void
        private let persistTargetAction: @Sendable ([DeviceIdentifier], Int?) async -> Void

        init(
            sendCommand: @escaping @Sendable ([DeviceIdentifier], Int) async -> Void,
            persistTarget: @escaping @Sendable ([DeviceIdentifier], Int?) async -> Void
        ) {
            self.sendCommandAction = sendCommand
            self.persistTargetAction = persistTarget
        }

        func sendCommand(deviceIds: [DeviceIdentifier], position: Int) async {
            await sendCommandAction(deviceIds, position)
        }

        func persistTarget(deviceIds: [DeviceIdentifier], target: Int?) async {
            await persistTargetAction(deviceIds, target)
        }
    }
}
