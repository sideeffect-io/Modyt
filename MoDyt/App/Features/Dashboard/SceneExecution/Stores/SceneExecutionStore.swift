import Observation

enum SceneExecutionResult: Sendable, Equatable {
    case acknowledged(statusCode: Int)
    case rejected(statusCode: Int)
    case sentWithoutAcknowledgement
    case invalidSceneIdentifier
    case sendFailed
}

struct SceneExecutionState: Sendable, Equatable {
    var isExecuting = false
    var feedback: SceneExecutionFeedback?

    static let initial = SceneExecutionState()
}

enum SceneExecutionFeedback: Sendable, Equatable {
    case success
    case failure
    case sent
}

enum SceneExecutionEvent: Sendable {
    case executeTapped
    case executionFinished(SceneExecutionResult)
    case clearFeedback
}

enum SceneExecutionEffect: Sendable, Equatable {
    case executeScene
    case clearFeedback
}

@Observable
@MainActor
final class SceneExecutionStore: StartableStore {
    struct StateMachine {
        static func reduce(
            _ state: SceneExecutionState,
            _ event: SceneExecutionEvent
        ) -> Transition<SceneExecutionState, SceneExecutionEffect> {
            var state = state

            switch event {
            case .executeTapped:
                guard !state.isExecuting else { return .init(state: state) }
                state.isExecuting = true
                state.feedback = nil
                return .init(state: state, effects: [.executeScene])

            case .executionFinished(let result):
                state.isExecuting = false
                switch result {
                case .acknowledged:
                    state.feedback = .success
                case .rejected, .invalidSceneIdentifier, .sendFailed:
                    state.feedback = .failure
                case .sentWithoutAcknowledgement:
                    state.feedback = .sent
                }
                return .init(state: state, effects: [.clearFeedback])

            case .clearFeedback:
                state.feedback = nil
                return .init(state: state)
            }
        }
    }

    private(set) var state: SceneExecutionState = .initial

    private let executeScene: ExecuteSceneEffectExecutor
    private let clearFeedback: ClearSceneExecutionFeedbackEffectExecutor
    private var executionTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var hasStarted = false

    init(
        executeScene: ExecuteSceneEffectExecutor,
        clearFeedback: ClearSceneExecutionFeedbackEffectExecutor
    ) {
        self.executeScene = executeScene
        self.clearFeedback = clearFeedback
    }

    func start() {
        guard !hasStarted else { return }
        hasStarted = true
    }

    isolated deinit {
        executionTask?.cancel()
        feedbackTask?.cancel()
    }

    func send(_ event: SceneExecutionEvent) {
        let transition = StateMachine.reduce(state, event)
        state = transition.state
        handle(transition.effects)
    }

    private func handle(_ effects: [SceneExecutionEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: SceneExecutionEffect) {
        switch effect {
        case .executeScene:
            cancelTask(&feedbackTask)
            replaceTask(
                &executionTask,
                with: makeTrackedEventTask(
                    operation: { [executeScene] in
                        await executeScene()
                    },
                    onEvent: { [weak self] event in
                        self?.send(event)
                    },
                    onFinish: { [weak self] in
                        self?.executionTask = nil
                    }
                )
            )

        case .clearFeedback:
            replaceTask(
                &feedbackTask,
                with: makeTrackedEventTask(
                    operation: { [clearFeedback] in
                        await clearFeedback()
                    },
                    onEvent: { [weak self] event in
                        self?.send(event)
                    },
                    onFinish: { [weak self] in
                        self?.feedbackTask = nil
                    }
                )
            )
        }
    }
}
