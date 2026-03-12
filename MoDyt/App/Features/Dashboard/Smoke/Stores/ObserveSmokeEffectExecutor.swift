import Foundation

struct ObserveSmokeEffectExecutor: Sendable {
    let observeSmoke: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<SmokeStore.Event> {
        let stream = await observeSmoke()
        return makeEventStream(from: stream) { device in
            SmokeStore.observationEvent(from: device)
        }
    }
}
