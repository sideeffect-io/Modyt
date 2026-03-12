import Foundation

struct ObserveSingleShutterEffectExecutor: Sendable {
    let observeDevice: @Sendable (DeviceIdentifier) async -> any AsyncSequence<Device?, Never> & Sendable

    @concurrent
    func callAsFunction(_ deviceId: DeviceIdentifier) async -> AsyncStream<SingleShutterEvent> {
        AsyncStream { continuation in
            let task = Task {
                let stream = await observeDevice(deviceId)
                var previousSnapshot: (position: Int, pendingLocalTarget: Int?)?

                for await device in stream {
                    guard !Task.isCancelled else { break }

                    let snapshot = (
                        position: device?.shutterPosition ?? 0,
                        pendingLocalTarget: device?.shutterTargetPosition
                    )

                    if let previousSnapshot {
                        if previousSnapshot.pendingLocalTarget != snapshot.pendingLocalTarget {
                            continuation.yield(
                                .pendingLocalTargetWasObserved(target: snapshot.pendingLocalTarget)
                            )
                        }
                        if previousSnapshot.position != snapshot.position {
                            continuation.yield(.positionWasReceived(position: snapshot.position))
                        }
                    } else {
                        if snapshot.pendingLocalTarget != nil {
                            continuation.yield(
                                .pendingLocalTargetWasObserved(target: snapshot.pendingLocalTarget)
                            )
                        }
                        continuation.yield(.positionWasReceived(position: snapshot.position))
                    }

                    previousSnapshot = snapshot
                }

                continuation.finish()
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
