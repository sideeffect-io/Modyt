import Foundation

struct PersistSingleShutterTargetEffectExecutor: Sendable {
    let persistTarget: @Sendable (DeviceIdentifier, Int?) async -> Void

    @concurrent
    func callAsFunction(
        deviceId: DeviceIdentifier,
        target: Int?
    ) async {
        await persistTarget(deviceId, target)
    }
}
