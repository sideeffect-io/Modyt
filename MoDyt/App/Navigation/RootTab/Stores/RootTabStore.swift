import Foundation
import Observation

struct RootTabState: Sendable, Equatable {
    struct InitialLoad: Sendable, Equatable {
        var errorMessage: String?
    }

    var isAppActive: Bool
    var isForegroundReconnectInFlight: Bool
    var didDisconnect: Bool
    var isInitialLoadBlocking: Bool
    var initialLoad: InitialLoad

    static let initial = RootTabState(
        isAppActive: true,
        isForegroundReconnectInFlight: false,
        didDisconnect: false,
        isInitialLoadBlocking: true,
        initialLoad: InitialLoad(errorMessage: nil)
    )
}

enum RootTabBootstrapResult: Sendable, Equatable {
    case completed
    case failed(String)
}

enum RootTabForegroundRecoveryResult: Sendable, Equatable {
    case alive
    case reconnected
    case failed
}

enum RootTabEvent: Sendable {
    case onStart
    case setAppActive(Bool)
    case foregroundRecoveryFinished(RootTabForegroundRecoveryResult)
    case bootstrapFinished(RootTabBootstrapResult)
    case disconnectCompleted
    case retryInitialLoad
}

enum RootTabEffect: Sendable, Equatable {
    case bootstrapGateway
    case setAppActive(Bool)
    case runForegroundRecovery
    case restartGatewayBootstrap
    case requestDisconnect
}

enum RootTabReducer {
    static func reduce(
        state: RootTabState,
        event: RootTabEvent
    ) -> (RootTabState, [RootTabEffect]) {
        var state = state
        var effects: [RootTabEffect] = []

        switch event {
        case .onStart:
            effects = [.bootstrapGateway]

        case .setAppActive(let isActive):
            let wasActive = state.isAppActive
            state.isAppActive = isActive

            if isActive {
                if wasActive {
                    effects = [.setAppActive(true)]
                } else {
                    state.isForegroundReconnectInFlight = true
                    effects = [.runForegroundRecovery]
                }
            } else if wasActive {
                state.isForegroundReconnectInFlight = false
                effects = [.setAppActive(false)]
            } else {
                state.isForegroundReconnectInFlight = false
            }

        case .foregroundRecoveryFinished(let result):
            guard state.isAppActive else {
                state.isForegroundReconnectInFlight = false
                return (state, effects)
            }

            state.isForegroundReconnectInFlight = false
            switch result {
            case .alive:
                effects = [.setAppActive(true)]
            case .reconnected:
                effects = [
                    .setAppActive(true),
                    .restartGatewayBootstrap
                ]
            case .failed:
                state.didDisconnect = false
                effects = [.requestDisconnect]
            }

        case .bootstrapFinished(let result):
            switch result {
            case .completed:
                state.initialLoad.errorMessage = nil
                state.isInitialLoadBlocking = false
            case .failed(let message):
                state.initialLoad.errorMessage = message
                state.isInitialLoadBlocking = true
            }

        case .disconnectCompleted:
            state.didDisconnect = true

        case .retryInitialLoad:
            state.initialLoad.errorMessage = nil
            state.isInitialLoadBlocking = true
            effects = [.restartGatewayBootstrap]
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class RootTabStore {
    struct Dependencies {
        let bootstrapGateway: @Sendable () async -> RootTabBootstrapResult
        let setAppActive: @Sendable (Bool) async -> Void
        let runForegroundRecovery: @Sendable () async -> RootTabForegroundRecoveryResult
        let requestDisconnect: @Sendable () async -> Void
    }

    private(set) var state: RootTabState

    private let bootstrapTask = TaskHandle()
    private let worker: Worker

    init(dependencies: Dependencies) {
        self.state = .initial
        self.worker = Worker(
            bootstrapGateway: dependencies.bootstrapGateway,
            setAppActive: dependencies.setAppActive,
            runForegroundRecovery: dependencies.runForegroundRecovery,
            requestDisconnect: dependencies.requestDisconnect
        )
    }

    func send(_ event: RootTabEvent) {
        let (nextState, effects) = RootTabReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [RootTabEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: RootTabEffect) {
        switch effect {
        case .bootstrapGateway:
            guard bootstrapTask.task == nil else { return }
            bootstrapTask.task = Task { [weak self, worker] in
                let result = await worker.bootstrapGateway()
                guard !Task.isCancelled else { return }
                self?.receive(.bootstrapFinished(result))
            }

        case .restartGatewayBootstrap:
            bootstrapTask.task = Task { [weak self, worker] in
                let result = await worker.bootstrapGateway()
                guard !Task.isCancelled else { return }
                self?.receive(.bootstrapFinished(result))
            }

        case .setAppActive(let isActive):
            Task { [worker] in
                await worker.setAppActive(isActive)
            }

        case .runForegroundRecovery:
            Task { [weak self, worker] in
                let result = await worker.runForegroundRecovery()
                guard !Task.isCancelled else { return }
                self?.receive(.foregroundRecoveryFinished(result))
            }

        case .requestDisconnect:
            Task { [weak self, worker] in
                await worker.requestDisconnect()
                self?.receive(.disconnectCompleted)
            }
        }
    }

    private func receive(_ event: RootTabEvent) {
        send(event)
    }

    private actor Worker {
        private let bootstrapGatewayAction: @Sendable () async -> RootTabBootstrapResult
        private let setAppActiveAction: @Sendable (Bool) async -> Void
        private let runForegroundRecoveryAction: @Sendable () async -> RootTabForegroundRecoveryResult
        private let requestDisconnectAction: @Sendable () async -> Void

        init(
            bootstrapGateway: @escaping @Sendable () async -> RootTabBootstrapResult,
            setAppActive: @escaping @Sendable (Bool) async -> Void,
            runForegroundRecovery: @escaping @Sendable () async -> RootTabForegroundRecoveryResult,
            requestDisconnect: @escaping @Sendable () async -> Void
        ) {
            self.bootstrapGatewayAction = bootstrapGateway
            self.setAppActiveAction = setAppActive
            self.runForegroundRecoveryAction = runForegroundRecovery
            self.requestDisconnectAction = requestDisconnect
        }

        func bootstrapGateway() async -> RootTabBootstrapResult {
            await bootstrapGatewayAction()
        }

        func setAppActive(_ isActive: Bool) async {
            await setAppActiveAction(isActive)
        }

        func runForegroundRecovery() async -> RootTabForegroundRecoveryResult {
            await runForegroundRecoveryAction()
        }

        func requestDisconnect() async {
            await requestDisconnectAction()
        }
    }
}

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}
