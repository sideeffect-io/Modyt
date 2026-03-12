import Foundation

struct SendGroupShutterCommandEffectExecutor: Sendable {
    let sendCommand: @Sendable ([DeviceIdentifier], Int) async -> Void

    @concurrent
    func callAsFunction(
        deviceIds: [DeviceIdentifier],
        position: Int
    ) async {
        await sendCommand(deviceIds, position)
    }
}
