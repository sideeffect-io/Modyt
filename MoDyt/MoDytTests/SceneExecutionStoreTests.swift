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
                feedbackDuration: .seconds(30)
            )
        )

        store.send(.executeTapped)
        let didStart = await waitUntil {
            let values = await recorder.values
            return store.state.isExecuting && values == ["execute:scene_42"]
        }

        #expect(didStart)
        #expect(store.state.isExecuting)
        #expect(await recorder.values == ["execute:scene_42"])

        await gate.resume(with: .acknowledged(statusCode: 200))
        let didSucceed = await waitUntil {
            !store.state.isExecuting && store.state.feedback == .success
        }

        #expect(didSucceed)
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
                feedbackDuration: .seconds(30)
            )
        )

        store.send(.executeTapped)
        let didFail = await waitUntil {
            !store.state.isExecuting && store.state.feedback == .failure
        }

        #expect(didFail)
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
                minimumExecutionAnimationDuration: .zero,
                feedbackDuration: .seconds(30)
            )
        )

        store.send(.executeTapped)
        store.send(.executeTapped)
        let didStartOnce = await waitUntil {
            let values = await recorder.values
            return values == ["execute:scene_99"]
        }

        #expect(didStartOnce)
        #expect(await recorder.values == ["execute:scene_99"])

        await gate.resume(with: .sentWithoutAcknowledgement)
        let didFinish = await waitUntil {
            !store.state.isExecuting && store.state.feedback == .sent
        }
        #expect(didFinish)
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
