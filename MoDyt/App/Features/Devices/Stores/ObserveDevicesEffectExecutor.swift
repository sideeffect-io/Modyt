import Foundation

struct ObserveDevicesEffectExecutor: Sendable {
    let observeDevices: @Sendable () async -> any AsyncSequence<[Device], Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<DevicesEvent> {
        let stream = await observeDevices()
        return makeEventStream(from: stream) { devices in
            .devicesObserved(devices)
        }
    }
}
