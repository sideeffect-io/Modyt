import Foundation

struct ClearSceneExecutionFeedbackEffectExecutor: Sendable {
    let clearFeedback: @Sendable () async -> Void

    @concurrent
    func callAsFunction() async -> SceneExecutionEvent? {
        await clearFeedback()
        return .clearFeedback
    }
}
