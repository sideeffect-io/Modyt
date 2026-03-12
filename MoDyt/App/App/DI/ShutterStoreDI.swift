import DeltaDoreClient

struct SingleShutterStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (DeviceIdentifier) -> SingleShutterStore

    init(make: @escaping @MainActor @Sendable (DeviceIdentifier) -> SingleShutterStore) {
        self.makeStore = make
    }

    @MainActor
    func make(deviceId: DeviceIdentifier) -> SingleShutterStore {
        makeStore(deviceId)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self { deviceId in
            SingleShutterStore(
                deviceId: deviceId,
                observeDevice: .init(
                    observeDevice: { await deviceRepository.observeByID($0) }
                ),
                sendCommand: .init(
                    sendCommand: { deviceId, targetPosition in
                        let command = makeShutterCommand(
                            for: deviceId,
                            targetPosition: targetPosition
                        )
                        try? await gatewayClient.send(text: command.request)
                    }
                ),
                startTimeout: .init(
                    sleep: { try await Task.sleep(for: $0) }
                ),
                persistTarget: .init(
                    persistTarget: { try? await deviceRepository.setShutterTargetPosition(deviceId: $0, target: $1) }
                )
            )
        }
    }
}

struct GroupShutterStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable ([DeviceIdentifier]) -> GroupShutterStore

    init(make: @escaping @MainActor @Sendable ([DeviceIdentifier]) -> GroupShutterStore) {
        self.makeStore = make
    }

    @MainActor
    func make(deviceIds: [DeviceIdentifier]) -> GroupShutterStore {
        makeStore(deviceIds)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self { deviceIds in
            GroupShutterStore(
                deviceIds: deviceIds,
                sendCommand: .init(
                    sendCommand: { requestedDeviceIds, targetPosition in
                        for deviceId in requestedDeviceIds.uniquePreservingOrder() {
                            let command = makeShutterCommand(
                                for: deviceId,
                                targetPosition: targetPosition
                            )
                            try? await gatewayClient.send(text: command.request)
                        }
                    }
                ),
                persistTarget: .init(
                    persistTarget: { requestedDeviceIds, target in
                        let uniqueDeviceIds = requestedDeviceIds.uniquePreservingOrder()
                        guard uniqueDeviceIds.isEmpty == false else { return }
                        try? await deviceRepository.setShutterTargetPosition(
                            deviceIds: uniqueDeviceIds,
                            target: target
                        )
                    }
                )
            )
        }
    }
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
