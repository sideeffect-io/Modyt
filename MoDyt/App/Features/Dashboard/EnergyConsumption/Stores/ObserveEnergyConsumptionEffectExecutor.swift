import Foundation

struct ObserveEnergyConsumptionEffectExecutor: Sendable {
    let observeEnergyConsumption: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<EnergyConsumptionStore.Event> {
        let stream = await observeEnergyConsumption()
        return makeEventStream(from: stream) { device in
            EnergyConsumptionStore.observationEvent(from: device)
        }
    }
}
