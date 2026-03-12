import Foundation

struct ObserveSunlightEffectExecutor: Sendable {
    let observeSunlight: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<SunlightStore.Event> {
        let stream = await observeSunlight()
        return makeEventStream(from: stream) { device in
            SunlightStore.observationEvent(from: device)
        }
    }
}
