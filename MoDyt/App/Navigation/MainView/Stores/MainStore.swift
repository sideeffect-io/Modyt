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
        var state: MainState = .initial

        mutating func reduce(_ event: MainEvent) -> [MainEffect] {
            switch (state.featureState, event) {
            case (.featureIsIdle, .startingGatewayHandlingWasRequested):
                state.featureState = .gatewayHandlingIsStarting
                return [.handleGatewayMessages]

            case (.gatewayHandlingIsStarting, .gatewayHandlingWasAFailure):
                state.featureState = .gatewayHandlingIsInError
                return []

            case (.gatewayHandlingIsInError, .startingGatewayHandlingWasRequested):
                state.featureState = .gatewayHandlingIsStarting
                return [.handleGatewayMessages]

            case (.gatewayHandlingIsInError, .disconnectionWasRequested):
                state.featureState = .disconnectionIsInProgress
                return [.disconnect]

            case (.disconnectionIsInProgress, .disconnectionWasSuccessful):
                state.featureState = .userIsDisconnected
                return []

            case (.gatewayHandlingIsStarting, .gatewayHandlingWasSuccessful):
                state.featureState = .featureIsStarted
                return [.setAppActive]

            case (.featureIsStarted, .appInactiveWasReceived):
                return [.setAppInactive]

            case (.featureIsStarted, .appActiveWasReceived):
                return [.checkGatewayConnection]

            case (.featureIsStarted, .reconnectionWasRequested):
                state.featureState = .reconnectionIsInProgress
                return [.reconnectToGateway]

            case (.reconnectionIsInProgress, .reconnectionWasAFailure):
                state.featureState = .reconnectionIsInError
                return []

            case (.reconnectionIsInError, .reconnectionWasRequested):
                state.featureState = .reconnectionIsInProgress
                return [.reconnectToGateway]

            case (.reconnectionIsInError, .disconnectionWasRequested):
                state.featureState = .disconnectionIsInProgress
                return [.disconnect]

            case (.reconnectionIsInProgress, .reconnectionWasSuccessful):
                state.featureState = .gatewayHandlingIsStarting
                return [.handleGatewayMessages]

            default:
                return []
            }
        }
    }

    struct Dependencies {
        let handleGatewayMessages: @Sendable () async -> MainEvent
        let disconnect: @Sendable () async -> Void
        let setAppInactive: @Sendable () async -> Void
        let setAppActive: @Sendable () async -> Void
        let checkGatewayConnection: @Sendable () async -> MainEvent?
        let reconnectToGateway: @Sendable () async -> MainEvent
    }

    private(set) var stateMachine: StateMachine = StateMachine()

    var state: MainState {
        stateMachine.state
    }

    private let gatewayHandlingTask = TaskHandle()
    private let disconnectTask = TaskHandle()
    private let appActivityTask = TaskHandle()
    private let checkConnectionTask = TaskHandle()
    private let reconnectTask = TaskHandle()
    private let worker: Worker
    private var hasStarted = false

    init(dependencies: Dependencies) {
        self.worker = Worker(
            handleGatewayMessages: dependencies.handleGatewayMessages,
            disconnect: dependencies.disconnect,
            setAppInactive: dependencies.setAppInactive,
            setAppActive: dependencies.setAppActive,
            checkGatewayConnection: dependencies.checkGatewayConnection,
            reconnectToGateway: dependencies.reconnectToGateway
        )
    }

    func send(_ event: MainEvent) {
        let effects = stateMachine.reduce(event)
        handle(effects)
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
        send(.startingGatewayHandlingWasRequested)
    }

    deinit {
        gatewayHandlingTask.cancel()
        disconnectTask.cancel()
        appActivityTask.cancel()
        checkConnectionTask.cancel()
        reconnectTask.cancel()
    }

    private func handle(_ effects: [MainEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: MainEffect) {
        switch effect {
        case .handleGatewayMessages:
            gatewayHandlingTask.task = Task { [weak self, worker] in
                let result = await worker.handleGatewayMessages()
                guard !Task.isCancelled else { return }
                self?.receive(result)
            }

        case .disconnect:
            cancelNonDisconnectTasks()
            disconnectTask.task = Task { [weak self, worker] in
                await worker.disconnect()
                guard !Task.isCancelled else { return }
                self?.receive(.disconnectionWasSuccessful)
            }

        case .setAppInactive:
            appActivityTask.task = Task { [worker] in
                await worker.setAppInactive()
            }

        case .setAppActive:
            appActivityTask.task = Task { [worker] in
                await worker.setAppActive()
            }

        case .checkGatewayConnection:
            checkConnectionTask.task = Task { [weak self, worker] in
                let event = await worker.checkGatewayConnection()
                guard !Task.isCancelled else { return }
                if let event {
                    self?.receive(event)
                }
            }

        case .reconnectToGateway:
            reconnectTask.task = Task { [weak self, worker] in
                let result = await worker.reconnectToGateway()
                guard !Task.isCancelled else { return }
                self?.receive(result)
            }
        }
    }

    private func receive(_ event: MainEvent) {
        send(event)
    }

    private func cancelNonDisconnectTasks() {
        gatewayHandlingTask.cancel()
        appActivityTask.cancel()
        checkConnectionTask.cancel()
        reconnectTask.cancel()
    }

    private actor Worker {
        private let handleGatewayMessagesAction: @Sendable () async -> MainEvent
        private let disconnectAction: @Sendable () async -> Void
        private let setAppInactiveAction: @Sendable () async -> Void
        private let setAppActiveAction: @Sendable () async -> Void
        private let checkGatewayConnectionAction: @Sendable () async -> MainEvent?
        private let reconnectToGatewayAction: @Sendable () async -> MainEvent

        init(
            handleGatewayMessages: @escaping @Sendable () async -> MainEvent,
            disconnect: @escaping @Sendable () async -> Void,
            setAppInactive: @escaping @Sendable () async -> Void,
            setAppActive: @escaping @Sendable () async -> Void,
            checkGatewayConnection: @escaping @Sendable () async -> MainEvent?,
            reconnectToGateway: @escaping @Sendable () async -> MainEvent
        ) {
            self.handleGatewayMessagesAction = handleGatewayMessages
            self.disconnectAction = disconnect
            self.setAppInactiveAction = setAppInactive
            self.setAppActiveAction = setAppActive
            self.checkGatewayConnectionAction = checkGatewayConnection
            self.reconnectToGatewayAction = reconnectToGateway
        }

        func handleGatewayMessages() async -> MainEvent {
            await handleGatewayMessagesAction()
        }

        func disconnect() async {
            await disconnectAction()
        }

        func setAppInactive() async {
            await setAppInactiveAction()
        }

        func setAppActive() async {
            await setAppActiveAction()
        }

        func checkGatewayConnection() async -> MainEvent? {
            await checkGatewayConnectionAction()
        }

        func reconnectToGateway() async -> MainEvent {
            await reconnectToGatewayAction()
        }
    }
}
