import Foundation

struct ObserveSingleLightEffectExecutor: Sendable {
    let observeLight: @Sendable () async -> any AsyncSequence<Device?, Never> & Sendable

    @concurrent
    func callAsFunction() async -> AsyncStream<SingleLightEvent> {
        AsyncStream { continuation in
            let task = Task {
                let stream = await observeLight()
                var previousDescriptor: DrivingLightControlDescriptor?

                for await device in stream {
                    guard !Task.isCancelled else { break }

                    let descriptor = device?.drivingLightControlDescriptor()
                    guard descriptor != previousDescriptor else { continue }

                    continuation.yield(.gatewayDescriptorWasReceived(descriptor))
                    previousDescriptor = descriptor
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
