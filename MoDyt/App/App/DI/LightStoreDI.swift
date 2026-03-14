import DeltaDoreClient

struct SingleLightStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable (DeviceIdentifier) -> SingleLightStore

    init(make: @escaping @MainActor @Sendable (DeviceIdentifier) -> SingleLightStore) {
        self.makeStore = make
    }

    @MainActor
    func make(deviceId: DeviceIdentifier) -> SingleLightStore {
        makeStore(deviceId)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self { deviceId in
            SingleLightStore(
                deviceId: deviceId,
                observeLight: .init(
                    observeLight: {
                        await deviceRepository.observeByID(deviceId)
                    }
                ),
                sendCommand: .init(
                    sendCommand: { command in
                        for request in gatewayRequests(for: command) {
                            let gatewayCommand = makeLightCommand(for: request)
                            try? await gatewayClient.send(text: gatewayCommand.request)
                        }
                    }
                )
            )
        }
    }
}

struct GroupLightStoreFactory: Sendable {
    private let makeStore: @MainActor @Sendable ([DeviceIdentifier]) -> GroupLightStore

    init(make: @escaping @MainActor @Sendable ([DeviceIdentifier]) -> GroupLightStore) {
        self.makeStore = make
    }

    @MainActor
    func make(deviceIds: [DeviceIdentifier]) -> GroupLightStore {
        makeStore(deviceIds)
    }

    static func live(dependencyBag: DependencyBag) -> Self {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let gatewayClient = dependencyBag.gatewayClient

        return Self { deviceIds in
            GroupLightStore(
                deviceIds: deviceIds,
                sendCommand: .init(
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
                ),
            )
        }
    }
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
        case .string(let value):
            return .string(value)
        }
    }
}

private nonisolated func gatewayRequests(
    for command: SingleLightGatewayCommand
) -> [LightGatewayCommandRequest] {
    switch command {
    case .data(let request):
        return [request]
    case .color(let request):
        var requests = [LightGatewayCommandRequest]()

        if let colorModeSignalName = request.colorModeSignalName,
           let colorModeValue = request.colorModeValue {
            requests.append(
                LightGatewayCommandRequest(
                    deviceId: request.deviceId,
                    signalName: colorModeSignalName,
                    value: .string(colorModeValue)
                )
            )
        }

        requests.append(
            LightGatewayCommandRequest(
                deviceId: request.deviceId,
                signalName: request.signalName,
                value: request.value
            )
        )

        if let temperatureSignalName = request.temperatureSignalName,
           let temperatureValue = request.temperatureValue {
            requests.append(
                LightGatewayCommandRequest(
                    deviceId: request.deviceId,
                    signalName: temperatureSignalName,
                    value: temperatureValue
                )
            )
        }

        return requests
    }
}
