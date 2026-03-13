import Foundation
import Observation

enum MainFeatureState: Sendable, Equatable {
    case featureIsIdle
    case gatewayHandlingIsStarting
    case gatewayHandlingIsInError
    case disconnectionIsInProgress
    case userIsDisconnected
    case featureIsStarted
    case reconnectionIsInProgress
    case reconnectionIsInError
}

struct MainState: Sendable, Equatable {
    var featureState: MainFeatureState

    static let initial = MainState(featureState: .featureIsIdle)
}

enum MainEvent: Sendable, Equatable {
    case startingGatewayHandlingWasRequested
    case gatewayHandlingWasAFailure
    case disconnectionWasRequested
    case disconnectionWasSuccessful
    case gatewayHandlingWasSuccessful
    case appInactiveWasReceived
    case appActiveWasReceived
    case reconnectionWasRequested
    case reconnectionWasAFailure
    case reconnectionWasSuccessful
}

enum MainEffect: Sendable, Equatable {
    case handleGatewayMessages
    case disconnect
    case setAppInactive
    case setAppActive
    case checkGatewayConnection
    case reconnectToGateway
}

@Observable
@MainActor
final class MainStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: MainState,
            _ event: MainEvent
        ) -> Transition<MainState, MainEffect> {
            var state = state

            switch (state.featureState, event) {
            case (.featureIsIdle, .startingGatewayHandlingWasRequested):
                state.featureState = .gatewayHandlingIsStarting
                return .init(state: state, effects: [.handleGatewayMessages])

            case (.gatewayHandlingIsStarting, .gatewayHandlingWasAFailure):
                state.featureState = .gatewayHandlingIsInError
                return .init(state: state)

            case (.gatewayHandlingIsInError, .startingGatewayHandlingWasRequested):
                state.featureState = .gatewayHandlingIsStarting
                return .init(state: state, effects: [.handleGatewayMessages])

            case (.gatewayHandlingIsInError, .disconnectionWasRequested):
                state.featureState = .disconnectionIsInProgress
                return .init(state: state, effects: [.disconnect])

            case (.disconnectionIsInProgress, .disconnectionWasSuccessful):
                state.featureState = .userIsDisconnected
                return .init(state: state)

            case (.gatewayHandlingIsStarting, .gatewayHandlingWasSuccessful):
                state.featureState = .featureIsStarted
                return .init(state: state, effects: [.setAppActive])

            case (.featureIsStarted, .appInactiveWasReceived):
                return .init(state: state, effects: [.setAppInactive])

            case (.featureIsStarted, .appActiveWasReceived):
                return .init(state: state, effects: [.checkGatewayConnection])

            case (.featureIsStarted, .reconnectionWasRequested):
                state.featureState = .reconnectionIsInProgress
                return .init(state: state, effects: [.reconnectToGateway])

            case (.reconnectionIsInProgress, .reconnectionWasAFailure):
                state.featureState = .reconnectionIsInError
                return .init(state: state)

            case (.reconnectionIsInError, .reconnectionWasRequested):
                state.featureState = .reconnectionIsInProgress
                return .init(state: state, effects: [.reconnectToGateway])

            case (.reconnectionIsInError, .disconnectionWasRequested):
                state.featureState = .disconnectionIsInProgress
                return .init(state: state, effects: [.disconnect])

            case (.reconnectionIsInProgress, .reconnectionWasSuccessful):
                state.featureState = .featureIsStarted
                return .init(state: state)

            default:
                return .init(state: state)
            }
        }
    }

    private(set) var state: MainState = .initial

    private let handleGatewayMessages: HandleMainGatewayMessagesEffectExecutor
    private let disconnect: DisconnectMainEffectExecutor
    private let setAppInactive: SetMainAppInactiveEffectExecutor
    private let setAppActive: SetMainAppActiveEffectExecutor
    private let checkGatewayConnection: CheckMainGatewayConnectionEffectExecutor
    private let reconnectToGateway: ReconnectMainGatewayEffectExecutor
    private var gatewayHandlingTask: Task<Void, Never>?
    private var disconnectTask: Task<Void, Never>?
    private var appActivityTask: Task<Void, Never>?
    private var checkConnectionTask: Task<Void, Never>?
    private var reconnectTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        handleGatewayMessages: HandleMainGatewayMessagesEffectExecutor,
        disconnect: DisconnectMainEffectExecutor,
        setAppInactive: SetMainAppInactiveEffectExecutor,
        setAppActive: SetMainAppActiveEffectExecutor,
        checkGatewayConnection: CheckMainGatewayConnectionEffectExecutor,
        reconnectToGateway: ReconnectMainGatewayEffectExecutor
    ) {
        self.handleGatewayMessages = handleGatewayMessages
        self.disconnect = disconnect
        self.setAppInactive = setAppInactive
        self.setAppActive = setAppActive
        self.checkGatewayConnection = checkGatewayConnection
        self.reconnectToGateway = reconnectToGateway
    }

    func send(_ event: MainEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.startingGatewayHandlingWasRequested)
    }

    isolated deinit {
        gatewayHandlingTask?.cancel()
        disconnectTask?.cancel()
        appActivityTask?.cancel()
        checkConnectionTask?.cancel()
        reconnectTask?.cancel()
    }

    private func handle(_ effects: [MainEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: MainEffect) {
        switch effect {
        case .handleGatewayMessages:
            replaceTask(
                &gatewayHandlingTask,
                with: makeTrackedEventTask(
                    operation: { [handleGatewayMessages] in
                        await handleGatewayMessages()
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    },
                    onFinish: { [weak self] in
                        self?.gatewayHandlingTask = nil
                    }
                )
            )

        case .disconnect:
            cancelNonDisconnectTasks()
            replaceTask(
                &disconnectTask,
                with: makeTrackedEventTask(
                    operation: { [disconnect] in
                        await disconnect()
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    },
                    onFinish: { [weak self] in
                        self?.disconnectTask = nil
                    }
                )
            )

        case .setAppInactive:
            replaceTask(
                &appActivityTask,
                with: makeTrackedEventTask(
                    operation: { [setAppInactive] in
                        await setAppInactive()
                        return nil
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    },
                    onFinish: { [weak self] in
                        self?.appActivityTask = nil
                    }
                )
            )

        case .setAppActive:
            replaceTask(
                &appActivityTask,
                with: makeTrackedEventTask(
                    operation: { [setAppActive] in
                        await setAppActive()
                        return nil
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    },
                    onFinish: { [weak self] in
                        self?.appActivityTask = nil
                    }
                )
            )

        case .checkGatewayConnection:
            replaceTask(
                &checkConnectionTask,
                with: makeTrackedEventTask(
                    operation: { [checkGatewayConnection] in
                        await checkGatewayConnection()
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    },
                    onFinish: { [weak self] in
                        self?.checkConnectionTask = nil
                    }
                )
            )

        case .reconnectToGateway:
            replaceTask(
                &reconnectTask,
                with: makeTrackedEventTask(
                    operation: { [reconnectToGateway] in
                        await reconnectToGateway()
                    },
                    onEvent: { [weak self] event in
                        self?.receive(event)
                    },
                    onFinish: { [weak self] in
                        self?.reconnectTask = nil
                    }
                )
            )
        }
    }

    private func receive(_ event: MainEvent) {
        send(event)
    }

    private func cancelNonDisconnectTasks() {
        cancelTask(&gatewayHandlingTask)
        cancelTask(&appActivityTask)
        cancelTask(&checkConnectionTask)
        cancelTask(&reconnectTask)
    }
}
