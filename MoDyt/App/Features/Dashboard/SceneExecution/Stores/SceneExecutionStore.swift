import Observation

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
    case executeScene(String)
    case clearFeedback
}

enum SceneExecutionReducer {
    static func reduce(
        state: SceneExecutionState,
        event: SceneExecutionEvent,
        uniqueId: String
    ) -> (SceneExecutionState, [SceneExecutionEffect]) {
        var state = state
        var effects: [SceneExecutionEffect] = []

        switch event {
        case .executeTapped:
            guard !state.isExecuting else { return (state, effects) }
            state.isExecuting = true
            state.feedback = nil
            effects = [.executeScene(uniqueId)]

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
            effects = [.clearFeedback]

        case .clearFeedback:
            state.feedback = nil
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class SceneExecutionStore {
    struct Dependencies {
        let executeScene: @Sendable (String) async -> SceneExecutionResult
        let sleep: @Sendable (Duration) async -> Void
        let minimumExecutionAnimationDuration: Duration
        let feedbackDuration: Duration

        init(
            executeScene: @escaping @Sendable (String) async -> SceneExecutionResult,
            sleep: @escaping @Sendable (Duration) async -> Void = { duration in
                try? await Task.sleep(for: duration)
            },
            minimumExecutionAnimationDuration: Duration = .seconds(2),
            feedbackDuration: Duration = .seconds(2)
        ) {
            self.executeScene = executeScene
            self.sleep = sleep
            self.minimumExecutionAnimationDuration = minimumExecutionAnimationDuration
            self.feedbackDuration = feedbackDuration
        }
    }

    private(set) var state: SceneExecutionState

    private let uniqueId: String
    private let executionTask = TaskHandle()
    private let feedbackTask = TaskHandle()
    private let worker: Worker

    init(uniqueId: String, dependencies: Dependencies) {
        self.state = .initial
        self.uniqueId = uniqueId
        self.worker = Worker(
            executeScene: dependencies.executeScene,
            sleep: dependencies.sleep,
            minimumExecutionAnimationDuration: dependencies.minimumExecutionAnimationDuration,
            feedbackDuration: dependencies.feedbackDuration
        )
    }

    func send(_ event: SceneExecutionEvent) {
        let (nextState, effects) = SceneExecutionReducer.reduce(
            state: state,
            event: event,
            uniqueId: uniqueId
        )
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [SceneExecutionEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: SceneExecutionEffect) {
        switch effect {
        case .executeScene(let uniqueId):
            feedbackTask.cancel()
            executionTask.cancel()
            let taskHandle = executionTask
            executionTask.task = Task { [weak self, worker, uniqueId, weak taskHandle] in
                defer {
                    Task { @MainActor [weak taskHandle] in
                        taskHandle?.task = nil
                    }
                }
                let result = await worker.executeScene(uniqueId)
                guard !Task.isCancelled else { return }
                self?.send(.executionFinished(result))
            }

        case .clearFeedback:
            feedbackTask.task = Task { [weak self, worker] in
                await worker.waitBeforeClearingFeedback()
                self?.send(.clearFeedback)
            }
        }
    }

    private actor Worker {
        private let executeSceneAction: @Sendable (String) async -> SceneExecutionResult
        private let sleepAction: @Sendable (Duration) async -> Void
        private let minimumExecutionAnimationDuration: Duration
        private let feedbackDuration: Duration

        init(
            executeScene: @escaping @Sendable (String) async -> SceneExecutionResult,
            sleep: @escaping @Sendable (Duration) async -> Void,
            minimumExecutionAnimationDuration: Duration,
            feedbackDuration: Duration
        ) {
            self.executeSceneAction = executeScene
            self.sleepAction = sleep
            self.minimumExecutionAnimationDuration = minimumExecutionAnimationDuration
            self.feedbackDuration = feedbackDuration
        }

        func executeScene(_ uniqueId: String) async -> SceneExecutionResult {
            async let result = executeSceneAction(uniqueId)
            await sleepAction(minimumExecutionAnimationDuration)
            return await result
        }

        func waitBeforeClearingFeedback() async {
            await sleepAction(feedbackDuration)
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
