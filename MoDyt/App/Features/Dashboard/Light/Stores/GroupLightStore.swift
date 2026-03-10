import Foundation
import Observation

enum GroupLightState: Sendable, Equatable {
    case featureIsIdle(deviceIds: [DeviceIdentifier])

    var deviceIds: [DeviceIdentifier] {
        switch self {
        case .featureIsIdle(let deviceIds):
            return deviceIds
        }
    }
}

enum GroupLightEvent: Sendable, Equatable {
    case presetWasTapped(LightPreset)
}

enum GroupLightEffect: Sendable, Equatable {
    case sendCommand(deviceIds: [DeviceIdentifier], preset: LightPreset)
}

@Observable
@MainActor
final class GroupLightStore: StartableStore {
    struct StateMachine {
        var state: GroupLightState = .featureIsIdle(deviceIds: [])

        mutating func reduce(_ event: GroupLightEvent) -> [GroupLightEffect] {
            switch (state, event) {
            case let (.featureIsIdle(deviceIds), .presetWasTapped(preset)):
                guard deviceIds.isEmpty == false else { return [] }
                return [.sendCommand(deviceIds: deviceIds, preset: preset)]
            }
        }
    }

    struct Dependencies {
        let sendCommand: @Sendable ([DeviceIdentifier], LightPreset) async -> Void

        init(
            sendCommand: @escaping @Sendable ([DeviceIdentifier], LightPreset) async -> Void
        ) {
            self.sendCommand = sendCommand
        }
    }

    private(set) var stateMachine: StateMachine

    var state: GroupLightState {
        stateMachine.state
    }

    private let worker: Worker

    init(
        deviceIds: [DeviceIdentifier],
        dependencies: Dependencies
    ) {
        self.stateMachine = StateMachine(
            state: .featureIsIdle(deviceIds: deviceIds.uniquePreservingOrder())
        )
        self.worker = Worker(sendCommand: dependencies.sendCommand)
    }

    func start() {}

    func send(_ event: GroupLightEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    private func handle(_ effects: [GroupLightEffect]) {
        for effect in effects {
            switch effect {
            case .sendCommand(let deviceIds, let preset):
                Task { [worker] in
                    await worker.sendCommand(deviceIds: deviceIds, preset: preset)
                }
            }
        }
    }

    private actor Worker {
        private let sendCommandAction: @Sendable ([DeviceIdentifier], LightPreset) async -> Void

        init(
            sendCommand: @escaping @Sendable ([DeviceIdentifier], LightPreset) async -> Void
        ) {
            self.sendCommandAction = sendCommand
        }

        func sendCommand(deviceIds: [DeviceIdentifier], preset: LightPreset) async {
            await sendCommandAction(deviceIds, preset)
        }
    }
}
