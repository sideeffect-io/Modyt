import Foundation

struct SendSingleLightCommandEffectExecutor: Sendable {
    let sendCommand: @Sendable (SingleLightGatewayCommand) async -> Void

    @concurrent
    func callAsFunction(_ command: SingleLightGatewayCommand) async {
        await sendCommand(command)
    }
}
