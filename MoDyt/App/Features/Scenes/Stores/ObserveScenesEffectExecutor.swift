import Foundation

struct ObserveScenesEffectExecutor: Sendable {
    let observeScenes: @Sendable () async -> any AsyncSequence<[Scene], Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<ScenesEvent> {
        let stream = await observeScenes()
        return makeEventStream(from: stream) { scenes in
            .scenesObserved(scenes)
        }
    }
}
