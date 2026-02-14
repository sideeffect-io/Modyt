import Foundation
import Observation

struct RootTabState: Sendable, Equatable {
    var isAppActive: Bool
    var isForegroundReconnectInFlight: Bool
    var didDisconnect: Bool

    static let initial = RootTabState(
        isAppActive: true,
        isForegroundReconnectInFlight: false,
        didDisconnect: false
    )
}

enum RootTabEvent: Sendable {
    case onStart
    case setAppActive(Bool)
    case foregroundRecoveryPhaseChanged(RootTabForegroundRecoveryPhase)
    case disconnectCompleted
}

enum RootTabForegroundRecoveryPhase: Sendable, Equatable {
    case alive
    case reconnecting
    case reconnected
    case failed
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
                    state.isForegroundReconnectInFlight = false
                    effects = [.runForegroundRecovery]
                }
            } else if wasActive {
                state.isForegroundReconnectInFlight = false
                effects = [.setAppActive(false)]
            } else {
                state.isForegroundReconnectInFlight = false
            }

        case .foregroundRecoveryPhaseChanged(let phase):
            guard state.isAppActive else {
                state.isForegroundReconnectInFlight = false
                return (state, effects)
            }

            switch phase {
            case .alive:
                state.isForegroundReconnectInFlight = false
                effects = [.setAppActive(true)]

            case .reconnecting:
                state.isForegroundReconnectInFlight = true
                effects = []

            case .reconnected:
                state.isForegroundReconnectInFlight = false
                effects = [
                    .setAppActive(true),
                    .restartGatewayBootstrap
                ]

            case .failed:
                state.isForegroundReconnectInFlight = false
                state.didDisconnect = false
                effects = [.requestDisconnect]
            }

        case .disconnectCompleted:
            state.didDisconnect = true
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class RootTabStore {
    struct Dependencies {
        let bootstrapGateway: @Sendable () async -> Void
        let setAppActive: @Sendable (Bool) async -> Void
        let runForegroundRecovery: @Sendable (
            @escaping @MainActor (RootTabForegroundRecoveryPhase) -> Void
        ) async -> Void
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
            bootstrapTask.task = Task { [worker] in
                await worker.bootstrapGateway()
            }

        case .restartGatewayBootstrap:
            bootstrapTask.task = Task { [worker] in
                await worker.bootstrapGateway()
            }

        case .setAppActive(let isActive):
            Task { [worker] in
                await worker.setAppActive(isActive)
            }

        case .runForegroundRecovery:
            Task { [weak self, worker] in
                await worker.runForegroundRecovery { phase in
                    self?.receive(.foregroundRecoveryPhaseChanged(phase))
                }
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
        private let bootstrapGatewayAction: @Sendable () async -> Void
        private let setAppActiveAction: @Sendable (Bool) async -> Void
        private let runForegroundRecoveryAction: @Sendable (
            @escaping @MainActor (RootTabForegroundRecoveryPhase) -> Void
        ) async -> Void
        private let requestDisconnectAction: @Sendable () async -> Void

        init(
            bootstrapGateway: @escaping @Sendable () async -> Void,
            setAppActive: @escaping @Sendable (Bool) async -> Void,
            runForegroundRecovery: @escaping @Sendable (
                @escaping @MainActor (RootTabForegroundRecoveryPhase) -> Void
            ) async -> Void,
            requestDisconnect: @escaping @Sendable () async -> Void
        ) {
            self.bootstrapGatewayAction = bootstrapGateway
            self.setAppActiveAction = setAppActive
            self.runForegroundRecoveryAction = runForegroundRecovery
            self.requestDisconnectAction = requestDisconnect
        }

        func bootstrapGateway() async {
            await bootstrapGatewayAction()
        }

        func setAppActive(_ isActive: Bool) async {
            await setAppActiveAction(isActive)
        }

        func runForegroundRecovery(
            _ onPhase: @escaping @MainActor (RootTabForegroundRecoveryPhase) -> Void
        ) async {
            await runForegroundRecoveryAction(onPhase)
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
