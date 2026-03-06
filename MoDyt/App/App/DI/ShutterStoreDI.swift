import SwiftUI
import DeltaDoreClient

enum ShutterStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> ShutterStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeDevices: { await deviceRepository.observeByIDs($0) },
            sendCommand: { requestedDeviceIds, targetPosition in
                for deviceId in requestedDeviceIds.uniquePreservingOrder() {
                    let command = makeShutterCommand(
                        for: deviceId,
                        targetPosition: targetPosition
                    )
                    try? await gatewayClient.send(text: command.request)
                }
            },
            sleep: { try await Task.sleep(for: $0) },
            persistTarget: { try? await deviceRepository.setShutterTargetPosition(deviceIds: $0, target: $1) }
        )
    }
}

extension EnvironmentValues {
    @Entry var shutterStoreDependencies: ShutterStore.Dependencies =
        ShutterStoreDependencyFactory.make()
}

private nonisolated func makeShutterCommand(
    for identifier: DeviceIdentifier,
    targetPosition: Int
) -> TydomCommand {
    let transactionId = TydomCommand.defaultTransactionId()
    return TydomCommand.putDevicesData(
        deviceId: String(identifier.deviceId),
        endpointId: String(identifier.endpointId),
        name: "position",
        value: .int(targetPosition),
        transactionId: transactionId
    )
}
