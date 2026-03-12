import Foundation
import DeltaDoreClient

struct ExecuteHeatPumpSetPointEffectExecutor: Sendable {
    let executeSetPointCommand: @Sendable (HeatPumpGatewayCommand) async -> Void
    let makeTransactionID: @Sendable () async -> String

    @concurrent
    func callAsFunction(
        setPoint: Double,
        commandContext: HeatPumpStore.CommandContext?
    ) async -> HeatPumpEvent? {
        guard let commandContext else {
            return .setPointWasConfirmed
        }

        let transactionId = await makeTransactionID()
        let command = TydomCommand.putDevicesData(
            deviceId: String(commandContext.deviceID),
            endpointId: String(commandContext.endpointID),
            name: commandContext.setPointName,
            value: .string(Self.formattedSetPoint(setPoint)),
            transactionId: transactionId
        )

        await executeSetPointCommand(
            HeatPumpGatewayCommand(
                request: command.request,
                transactionId: transactionId
            )
        )
        return .setPointWasConfirmed
    }

    private static func formattedSetPoint(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        formatter.usesGroupingSeparator = false
        return formatter.string(from: NSNumber(value: value)) ?? String(value)
    }
}
