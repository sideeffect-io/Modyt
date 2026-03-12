import Foundation

struct ObserveTemperatureEffectExecutor: Sendable {
    let observeTemperature: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<TemperatureStore.Event> {
        let stream = await observeTemperature()
        return makeEventStream(from: stream) { device in
            TemperatureStore.observationEvent(from: device)
        }
    }
}
