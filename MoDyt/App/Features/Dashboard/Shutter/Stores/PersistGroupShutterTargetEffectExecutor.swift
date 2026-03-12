import Foundation

struct PersistGroupShutterTargetEffectExecutor: Sendable {
    let persistTarget: @Sendable ([DeviceIdentifier], Int?) async -> Void

    @concurrent
    func callAsFunction(
        deviceIds: [DeviceIdentifier],
        target: Int?
    ) async {
        await persistTarget(deviceIds, target)
    }
}
