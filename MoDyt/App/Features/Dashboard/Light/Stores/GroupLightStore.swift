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
    case sendCommand(preset: LightPreset)
}

@Observable
@MainActor
final class GroupLightStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: GroupLightState,
            _ event: GroupLightEvent
        ) -> Transition<GroupLightState, GroupLightEffect> {
            switch (state, event) {
            case let (.featureIsIdle(deviceIds), .presetWasTapped(preset)):
                guard deviceIds.isEmpty == false else { return .init(state: state) }
                return .init(
                    state: state,
                    effects: [.sendCommand(preset: preset)]
                )
            }
        }
    }

    private(set) var state: GroupLightState

    private let sendCommand: SendGroupLightCommandEffectExecutor

    init(
        deviceIds: [DeviceIdentifier],
        sendCommand: SendGroupLightCommandEffectExecutor
    ) {
        self.state = .featureIsIdle(deviceIds: deviceIds.uniquePreservingOrder())
        self.sendCommand = sendCommand
    }

    func start() {}

    func send(_ event: GroupLightEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [GroupLightEffect]) {
        for effect in effects {
            switch effect {
            case .sendCommand(let preset):
                let deviceIds = state.deviceIds
                launchFireAndForgetTask { [deviceIds, preset, sendCommand] in
                    await sendCommand(deviceIds: deviceIds, preset: preset)
                }
            }
        }
    }
}
