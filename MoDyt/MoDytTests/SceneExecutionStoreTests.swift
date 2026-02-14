import Testing
@testable import MoDyt

@MainActor
struct SceneExecutionStoreTests {
    @Test
    func executeTappedDispatchesExecutionAndSetsSuccessFeedback() async {
        let recorder = TestRecorder<String>()
        let gate = SceneExecutionGate()
        let store = SceneExecutionStore(
            uniqueId: "scene_42",
            dependencies: .init(
                executeScene: { uniqueId in
                    await recorder.record("execute:\(uniqueId)")
                    return await gate.wait()
                },
                minimumExecutionAnimationDuration: .zero,
                feedbackDuration: .seconds(1)
            )
        )

        store.send(.executeTapped)
        await settleAsyncState()

        #expect(store.state.isExecuting)
        #expect(await recorder.values == ["execute:scene_42"])

        await gate.resume(with: .acknowledged(statusCode: 200))
        await settleAsyncState()

        #expect(!store.state.isExecuting)
        #expect(store.state.feedback == .success)
    }

    @Test
    func executionFailureSetsFailureFeedback() async {
        let store = SceneExecutionStore(
            uniqueId: "scene_7",
            dependencies: .init(
                executeScene: { _ in .rejected(statusCode: 503) },
                minimumExecutionAnimationDuration: .zero,
                feedbackDuration: .seconds(1)
            )
        )

        store.send(.executeTapped)
        await settleAsyncState()

        #expect(!store.state.isExecuting)
        #expect(store.state.feedback == .failure)
    }

    @Test
    func executeTappedDoesNotRunConcurrently() async {
        let recorder = TestRecorder<String>()
        let gate = SceneExecutionGate()
        let store = SceneExecutionStore(
            uniqueId: "scene_99",
            dependencies: .init(
                executeScene: { uniqueId in
                    await recorder.record("execute:\(uniqueId)")
                    return await gate.wait()
                },
                minimumExecutionAnimationDuration: .zero
            )
        )

        store.send(.executeTapped)
        store.send(.executeTapped)
        await settleAsyncState()

        #expect(await recorder.values == ["execute:scene_99"])

        await gate.resume(with: .sentWithoutAcknowledgement)
        await settleAsyncState()
    }
}

private actor SceneExecutionGate {
    private var continuation: CheckedContinuation<SceneExecutionResult, Never>?

    func wait() async -> SceneExecutionResult {
        await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func resume(with result: SceneExecutionResult) {
        continuation?.resume(returning: result)
        continuation = nil
    }
}
