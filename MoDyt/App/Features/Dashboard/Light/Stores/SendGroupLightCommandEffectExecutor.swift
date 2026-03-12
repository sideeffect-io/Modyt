import Foundation

struct SendGroupLightCommandEffectExecutor: Sendable {
    let sendCommand: @Sendable ([DeviceIdentifier], LightPreset) async -> Void

    @concurrent
    func callAsFunction(
        deviceIds: [DeviceIdentifier],
        preset: LightPreset
    ) async {
        await sendCommand(deviceIds, preset)
    }
}
