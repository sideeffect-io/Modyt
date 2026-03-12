import Foundation

struct ObserveHeatPumpEffectExecutor: Sendable {
    let observeHeatPump: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<HeatPumpObservation> {
        AsyncStream { continuation in
            let task = Task {
                let stream = await observeHeatPump()

                for await device in stream {
                    guard !Task.isCancelled else { break }
                    guard let device else { continue }
                    guard let values = device.heatPumpGatewayValues() else { continue }
                    guard let setPointName = device.heatPumpSetpointKey() else { continue }

                    continuation.yield(
                        HeatPumpObservation(
                            temperature: values.temperature,
                            setPoint: values.setPoint,
                            commandContext: HeatPumpStore.CommandContext(
                                deviceID: device.deviceId,
                                endpointID: device.endpointId,
                                setPointName: setPointName
                            )
                        )
                    )
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
