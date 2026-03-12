import Foundation

struct SendSingleShutterCommandEffectExecutor: Sendable {
    let sendCommand: @Sendable (DeviceIdentifier, Int) async -> Void

    @concurrent
    func callAsFunction(
        deviceId: DeviceIdentifier,
        position: Int
    ) async {
        await sendCommand(deviceId, position)
    }
}
