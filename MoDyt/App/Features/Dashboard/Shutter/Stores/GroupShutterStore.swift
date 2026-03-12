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
    case sendCommand(position: Int)
    case persistTarget(target: Int?)
}

@Observable
@MainActor
final class GroupShutterStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: GroupShutterState,
            _ event: GroupShutterEvent
        ) -> Transition<GroupShutterState, GroupShutterEffect> {
            switch (state, event) {
            case let (.featureIsIdle(deviceIds), .targetWasSetInApp(target)):
                guard deviceIds.isEmpty == false else { return .init(state: state) }
                return .init(
                    state: state,
                    effects: [
                        .sendCommand(position: target),
                        .persistTarget(target: target),
                    ]
                )
            }
        }
    }

    private(set) var state: GroupShutterState

    private let sendCommand: SendGroupShutterCommandEffectExecutor
    private let persistTarget: PersistGroupShutterTargetEffectExecutor

    init(
        deviceIds: [DeviceIdentifier],
        sendCommand: SendGroupShutterCommandEffectExecutor,
        persistTarget: PersistGroupShutterTargetEffectExecutor
    ) {
        self.state = .featureIsIdle(deviceIds: deviceIds.uniquePreservingOrder())
        self.sendCommand = sendCommand
        self.persistTarget = persistTarget
    }

    func start() {}

    func send(_ event: GroupShutterEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [GroupShutterEffect]) {
        for effect in effects {
            switch effect {
            case .sendCommand(let position):
                let deviceIds = state.deviceIds
                launchFireAndForgetTask { [deviceIds, position, sendCommand] in
                    await sendCommand(deviceIds: deviceIds, position: position)
                }

            case .persistTarget(let target):
                let deviceIds = state.deviceIds
                launchFireAndForgetTask { [deviceIds, target, persistTarget] in
                    await persistTarget(deviceIds: deviceIds, target: target)
                }
            }
        }
    }
}
