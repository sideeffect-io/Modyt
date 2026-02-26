import SwiftUI
import DeltaDoreClient

struct HeatPumpStoreFactory {
    let make: @MainActor (String) -> HeatPumpStore

    static func live(dependencies: DependencyBag) -> HeatPumpStoreFactory {
        let runtime = HeatPumpRuntime(
            deviceRepository: dependencies.localStorageDatasources.deviceRepository,
            gatewayClient: dependencies.gatewayClient
        )

        return HeatPumpStoreFactory { uniqueId in
            HeatPumpStore(
                uniqueId: uniqueId,
                dependencies: .init(
                    observeHeatPump: { uniqueId in
                        await runtime.observeHeatPump(uniqueId: uniqueId)
                    },
                    applyOptimisticChanges: { uniqueId, changes in
                        await runtime.applyOptimisticChanges(uniqueId: uniqueId, changes: changes)
                    },
                    sendCommand: { uniqueId, key, value in
                        await runtime.sendCommand(uniqueId: uniqueId, key: key, value: value)
                    },
                    now: Date.init
                )
            )
        }
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

private actor HeatPumpRuntime {
    private let deviceRepository: DeviceRepository
    private let gatewayClient: DeltaDoreClient
    private let transactionIDGenerator = TransactionIDGenerator()

    init(
        deviceRepository: DeviceRepository,
        gatewayClient: DeltaDoreClient
    ) {
        self.deviceRepository = deviceRepository
        self.gatewayClient = gatewayClient
    }

    func observeHeatPump(
        uniqueId: String
    ) async -> any AsyncSequence<Device?, Never> & Sendable {
        await deviceRepository.observeByID(uniqueId)
    }

    func applyOptimisticChanges(
        uniqueId: String,
        changes: [String: PayloadValue]
    ) async {
        guard changes.isEmpty == false else { return }
        guard let existing = try? await deviceRepository.get(uniqueId) else { return }

        let optimisticData = existing.data.merging(
            changes.mapValues(JSONValue.init(deltaDore:))
        ) { _, incoming in
            incoming
        }

        guard optimisticData != existing.data else { return }

        let upsert = DeviceUpsert(
            id: existing.id,
            endpointId: existing.endpointId,
            name: existing.name,
            usage: existing.usage,
            kind: existing.kind,
            data: optimisticData,
            metadata: existing.metadata
        )
        try? await deviceRepository.upsert([upsert])
    }

    func sendCommand(
        uniqueId: String,
        key: String,
        value: PayloadValue
    ) async {
        guard let device = try? await deviceRepository.get(uniqueId) else { return }

        let command = TydomCommand.putDevicesData(
            deviceId: String(device.deviceID),
            endpointId: String(device.endpointId),
            name: key,
            value: Self.deviceCommandValue(from: value),
            transactionId: await transactionIDGenerator.next()
        )

        try? await gatewayClient.send(text: command.request)
    }

    private static func deviceCommandValue(
        from value: PayloadValue
    ) -> TydomCommand.DeviceDataValue {
        switch value {
        case .bool(let flag):
            .bool(flag)
        case .number(let number):
            .int(Int(number.rounded()))
        case .string(let text):
            .string(text)
        case .null, .object, .array:
            .null
        }
    }
}

private actor TransactionIDGenerator {
    private var lastIssued: UInt64 = 0

    func next() -> String {
        let milliseconds = UInt64(Date().timeIntervalSince1970 * 1000)
        let candidate = milliseconds * 1_000
        if candidate <= lastIssued {
            lastIssued += 1
        } else {
            lastIssued = candidate
        }
        return String(lastIssued)
    }
}
