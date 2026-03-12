import Foundation

struct ExecuteSceneEffectExecutor: Sendable {
    let executeScene: @Sendable () async -> SceneExecutionResult

    @concurrent
    func callAsFunction() async -> SceneExecutionEvent? {
        .executionFinished(await executeScene())
    }
}
