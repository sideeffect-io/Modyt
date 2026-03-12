import Foundation

struct ObserveThermostatEffectExecutor: Sendable {
    let observeThermostat: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<ThermostatStore.Event> {
        let stream = await observeThermostat()
        return makeEventStream(from: stream) { device in
            ThermostatStore.observationEvent(from: device)
        }
    }
}
