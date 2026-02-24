import Foundation
import DeltaDoreClient

actor TydomMessageRepositoryRouter {
    private let deviceRepository: DeviceRepository
    private let groupRepository: GroupRepository
    private let sceneRepository: SceneRepository
    private let ackRepository: ACKRepository
    private let log: @Sendable (String) -> Void

    init(
        deviceRepository: DeviceRepository,
        groupRepository: GroupRepository,
        sceneRepository: SceneRepository,
        ackRepository: ACKRepository,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.deviceRepository = deviceRepository
        self.groupRepository = groupRepository
        self.sceneRepository = sceneRepository
        self.ackRepository = ackRepository
        self.log = log
    }

    func startIfNeeded() async throws {
        try await deviceRepository.startIfNeeded()
        try await groupRepository.startIfNeeded()
        try await sceneRepository.startIfNeeded()
        await ackRepository.startIfNeeded()
    }

    func ingest(_ message: TydomMessage) async {
        switch message {
        case .devices(let devices, _):
            do {
                try await deviceRepository.upsert(devices.map(DeviceUpsert.init(tydomDevice:)))
            } catch {
                log("Router failed to persist devices: \(error)")
            }
        case .groupMetadata(let metadata, _):
            do {
                try await groupRepository.upsertMetadata(metadata.map(GroupMetadataUpsert.init(tydomMetadata:)))
            } catch {
                log("Router failed to persist group metadata: \(error)")
            }
        case .groups(let groups, _):
            do {
                try await groupRepository.upsertMembership(groups.map(GroupMembershipUpsert.init(tydomGroup:)))
            } catch {
                log("Router failed to persist group membership: \(error)")
            }
        case .scenarios(let scenarios, _):
            do {
                try await sceneRepository.upsert(scenarios.map(SceneUpsert.init(tydomScene:)))
            } catch {
                log("Router failed to persist scenarios: \(error)")
            }
        case .ack(let ack, let metadata):
            await ackRepository.ingest(ack: ack, metadata: metadata)
        default:
            break
        }
    }
}

extension DeviceUpsert {
    init(tydomDevice: TydomDevice) {
        self.init(
            id: tydomDevice.uniqueId,
            endpointId: tydomDevice.endpointId,
            name: tydomDevice.name,
            usage: tydomDevice.usage,
            kind: tydomDevice.kind.repositoryRawValue,
            data: .init(deltaDore: tydomDevice.data),
            metadata: tydomDevice.metadata.map { .init(deltaDore: $0) }
        )
    }
}

extension GroupMetadataUpsert {
    init(tydomMetadata: TydomGroupMetadata) {
        self.init(
            id: String(tydomMetadata.id),
            name: tydomMetadata.name,
            usage: tydomMetadata.usage,
            picto: tydomMetadata.picto,
            isGroupUser: tydomMetadata.isGroupUser,
            isGroupAll: tydomMetadata.isGroupAll
        )
    }
}

extension GroupMembershipUpsert {
    init(tydomGroup: TydomGroup) {
        self.init(
            id: String(tydomGroup.id),
            memberUniqueIds: tydomGroup.devices.flatMap { device in
                device.endpoints.map { endpoint in
                    "\(endpoint.id)_\(device.id)"
                }
            }
        )
    }
}

extension SceneUpsert {
    init(tydomScene: TydomScenario) {
        self.init(
            id: String(tydomScene.id),
            name: tydomScene.name,
            type: tydomScene.type,
            picto: tydomScene.picto,
            ruleId: tydomScene.ruleId,
            payload: .init(deltaDore: tydomScene.payload),
            isGatewayInternal: tydomScene.type.caseInsensitiveCompare("RE2020") == .orderedSame
        )
    }
}

extension JSONValue {
    init(deltaDore value: PayloadValue) {
        switch value {
        case .string(let value):
            self = .string(value)
        case .number(let value):
            self = .number(value)
        case .bool(let value):
            self = .bool(value)
        case .object(let value):
            self = .object(value.mapValues(JSONValue.init(deltaDore:)))
        case .array(let values):
            self = .array(values.map(JSONValue.init(deltaDore:)))
        case .null:
            self = .null
        }
    }
}

private extension Dictionary where Key == String, Value == JSONValue {
    init(deltaDore values: [String: PayloadValue]) {
        self = values.mapValues(JSONValue.init(deltaDore:))
    }
}

private extension TydomDeviceKind {
    var repositoryRawValue: String {
        switch self {
        case .shutter:
            "shutter"
        case .window:
            "window"
        case .door:
            "door"
        case .garage:
            "garage"
        case .gate:
            "gate"
        case .light:
            "light"
        case .energy:
            "energy"
        case .smoke:
            "smoke"
        case .boiler:
            "boiler"
        case .alarm:
            "alarm"
        case .weather:
            "weather"
        case .water:
            "water"
        case .thermo:
            "thermo"
        case .other(let value):
            value
        }
    }
}
