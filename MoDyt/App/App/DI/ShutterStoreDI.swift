import SwiftUI
import DeltaDoreClient

enum SingleShutterStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> SingleShutterStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeDevice: { await deviceRepository.observeByID($0) },
            sendCommand: { deviceId, targetPosition in
                let command = makeShutterCommand(
                    for: deviceId,
                    targetPosition: targetPosition
                )
                try? await gatewayClient.send(text: command.request)
            },
            sleep: { try await Task.sleep(for: $0) },
            persistTarget: { try? await deviceRepository.setShutterTargetPosition(deviceId: $0, target: $1) }
        )
    }
}

enum GroupShutterStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> GroupShutterStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            sendCommand: { requestedDeviceIds, targetPosition in
                for deviceId in requestedDeviceIds.uniquePreservingOrder() {
                    let command = makeShutterCommand(
                        for: deviceId,
                        targetPosition: targetPosition
                    )
                    try? await gatewayClient.send(text: command.request)
                }
            },
            persistTarget: { requestedDeviceIds, target in
                let uniqueDeviceIds = requestedDeviceIds.uniquePreservingOrder()
                guard uniqueDeviceIds.isEmpty == false else { return }
                try? await deviceRepository.setShutterTargetPosition(
                    deviceIds: uniqueDeviceIds,
                    target: target
                )
            }
        )
    }
}

extension EnvironmentValues {
    @Entry var singleShutterStoreDependencies: SingleShutterStore.Dependencies =
        SingleShutterStoreDependencyFactory.make()

    @Entry var groupShutterStoreDependencies: GroupShutterStore.Dependencies =
        GroupShutterStoreDependencyFactory.make()
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
