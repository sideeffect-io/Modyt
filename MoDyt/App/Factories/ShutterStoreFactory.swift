import SwiftUI
import DeltaDoreClient

struct ShutterStoreFactory {
    let make: @MainActor ([DeviceIdentifier]) -> ShutterStore

    static func live(dependencies: DependencyBag) -> ShutterStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository
        let gatewayClient = dependencies.gatewayClient

        return ShutterStoreFactory { deviceIds in
            let orderedDeviceIds = deviceIds.uniquePreservingOrder()
            return ShutterStore(
                deviceIds: orderedDeviceIds,
                dependencies: .init(
                    observeDevices: { await deviceRepository.observeByIDs($0) },
                    sendCommand: { requestedDeviceIds, targetPosition in
                        for deviceId in requestedDeviceIds.uniquePreservingOrder() {
                            let command = await makeShutterCommand(for: deviceId, targetPosition: targetPosition)
                            try? await gatewayClient.send(text: command.request)
                        }
                    },
                    sleep: {
                        try await Task.sleep(nanoseconds: timeoutNanoseconds)
                    },
                    setTarget: {
                        try? await deviceRepository.setShutterTargetPosition(deviceIds: $0, target: $1)
                    }
                )
            )
        }
    }

    private static let timeoutNanoseconds: UInt64 = 60_000_000_000

    private static func makeShutterCommand(
        for identifier: DeviceIdentifier,
        targetPosition: Int
    ) async -> TydomCommand {
        let transactionId = TydomCommand.defaultTransactionId()
        return TydomCommand.putDevicesData(
            deviceId: String(identifier.deviceId),
            endpointId: String(identifier.endpointId),
            name: "position",
            value: .int(targetPosition),
            transactionId: transactionId
        )
    }
}

private struct ShutterStoreFactoryKey: EnvironmentKey {
    static var defaultValue: ShutterStoreFactory {
        ShutterStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var shutterStoreFactory: ShutterStoreFactory {
        get { self[ShutterStoreFactoryKey.self] }
        set { self[ShutterStoreFactoryKey.self] = newValue }
    }
}
