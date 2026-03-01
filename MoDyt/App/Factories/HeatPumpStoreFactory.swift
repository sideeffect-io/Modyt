import SwiftUI
import DeltaDoreClient

struct HeatPumpStoreFactory {
    let make: @MainActor (DeviceIdentifier) -> HeatPumpStore
    
    static func live(dependencies: DependencyBag) -> HeatPumpStoreFactory {
        let deviceRepository = dependencies.localStorageDatasources.deviceRepository
        let gatewayClient = dependencies.gatewayClient
        let ackRepository = dependencies.localStorageDatasources.ackRepository
        
        return HeatPumpStoreFactory { identifier in
            HeatPumpStore(
                identifier: identifier,
                dependencies: .init(
                    observeHeatPump: { requestedIdentifier in
                        await deviceRepository
                            .observeByDeviceID(requestedIdentifier.deviceId)
                            .map { devices in
                                Self.resolveObservedDevice(
                                    for: requestedIdentifier,
                                    in: devices
                                )
                            }
                            .removeDuplicates()
                    },
                    executeSetPointCommand: { command in
                        try? await gatewayClient.send(text: command.request)
                        _ = try? await ackRepository.waitForACK(transactionId: command.transactionId)
                    },
                    makeTransactionID: {
                        TydomCommand.defaultTransactionId()
                    }
                )
            )
        }
    }

    static func resolveObservedDevice(
        for identifier: DeviceIdentifier,
        in devices: [Device]
    ) -> Device? {
        let siblingEndpoints = devices.filter { $0.deviceId == identifier.deviceId }
        guard siblingEndpoints.isEmpty == false else { return nil }

        guard let primaryDevice = siblingEndpoints.first(where: { $0.id == identifier })
            ?? siblingEndpoints.first else {
            return nil
        }

        var mergedData: [String: JSONValue] = [:]
        var mergedMetadata: [String: JSONValue] = [:]
        var hasMetadata = false

        for device in siblingEndpoints where device.id != primaryDevice.id {
            mergedData.merge(device.data) { _, next in next }
            if let metadata = device.metadata {
                mergedMetadata.merge(metadata) { _, next in next }
                hasMetadata = true
            }
        }

        mergedData.merge(primaryDevice.data) { _, next in next }
        if let metadata = primaryDevice.metadata {
            mergedMetadata.merge(metadata) { _, next in next }
            hasMetadata = true
        }

        var resolvedDevice = primaryDevice
        resolvedDevice.data = mergedData
        resolvedDevice.metadata = hasMetadata ? mergedMetadata : nil
        return resolvedDevice
    }
}

private struct HeatPumpStoreFactoryKey: EnvironmentKey {
    static var defaultValue: HeatPumpStoreFactory {
        HeatPumpStoreFactory.live(dependencies: .live())
    }
}

extension EnvironmentValues {
    var heatPumpStoreFactory: HeatPumpStoreFactory {
        get { self[HeatPumpStoreFactoryKey.self] }
        set { self[HeatPumpStoreFactoryKey.self] = newValue }
    }
}
