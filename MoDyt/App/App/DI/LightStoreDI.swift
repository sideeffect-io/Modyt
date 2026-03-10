import SwiftUI
import DeltaDoreClient

enum SingleLightStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> SingleLightStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeLight: { await deviceRepository.observeByID($0) },
            sendCommand: { request in
                let command = makeLightCommand(for: request)
                try? await gatewayClient.send(text: command.request)
            }
        )
    }
}

enum GroupLightStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> GroupLightStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            sendCommand: { requestedDeviceIds, preset in
                let uniqueDeviceIds = requestedDeviceIds.uniquePreservingOrder()
                guard uniqueDeviceIds.isEmpty == false else { return }

                let devices = (try? await deviceRepository.listByIDs(uniqueDeviceIds)) ?? []
                let devicesById = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })

                for deviceId in uniqueDeviceIds {
                    guard let device = devicesById[deviceId],
                          let descriptor = device.drivingLightControlDescriptor(),
                          let levelKey = descriptor.levelKey else {
                        continue
                    }

                    let rawLevel: Int
                    switch preset {
                    case .on:
                        rawLevel = descriptor.maximumLevel
                    case .half:
                        rawLevel = descriptor.rawLevel(forNormalizedLevel: 0.5)
                    case .off:
                        rawLevel = descriptor.minimumLevel
                    }

                    let request = LightGatewayCommandRequest(
                        deviceId: deviceId,
                        signalName: levelKey,
                        value: .int(rawLevel)
                    )
                    let command = makeLightCommand(for: request)
                    try? await gatewayClient.send(text: command.request)
                }
            }
        )
    }
}

extension EnvironmentValues {
    @Entry var singleLightStoreDependencies: SingleLightStore.Dependencies =
        SingleLightStoreDependencyFactory.make()

    @Entry var groupLightStoreDependencies: GroupLightStore.Dependencies =
        GroupLightStoreDependencyFactory.make()
}

private nonisolated func makeLightCommand(
    for request: LightGatewayCommandRequest
) -> TydomCommand {
    let transactionId = TydomCommand.defaultTransactionId()
    return TydomCommand.putDevicesData(
        deviceId: String(request.deviceId.deviceId),
        endpointId: String(request.deviceId.endpointId),
        name: request.signalName,
        value: request.value.asTydomValue,
        transactionId: transactionId
    )
}

private extension LightGatewayCommandValue {
    var asTydomValue: TydomCommand.DeviceDataValue {
        switch self {
        case .bool(let value):
            return .bool(value)
        case .int(let value):
            return .int(value)
        }
    }
}
