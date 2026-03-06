import SwiftUI
import DeltaDoreClient

enum LightStoreDependencyFactory {
    static func make(
        dependencyBag: DependencyBag = .production
    ) -> LightStore.Dependencies {
        let deviceRepository = dependencyBag.localStorageDatasources.deviceRepository
        let groupRepository = dependencyBag.localStorageDatasources.groupRepository
        let gatewayClient = dependencyBag.gatewayClient

        return .init(
            observeLightDescriptor: { uniqueId in
                await observeLightDescriptor(
                    uniqueId: uniqueId,
                    deviceRepository: deviceRepository,
                    groupRepository: groupRepository
                )
            },
            applyOptimisticChanges: { uniqueId, changes in
                await applyOptimisticChanges(
                    uniqueId: uniqueId,
                    changes: changes,
                    deviceRepository: deviceRepository,
                    groupRepository: groupRepository
                )
            },
            sendCommand: { uniqueId, key, value in
                await sendLightCommand(
                    uniqueId: uniqueId,
                    key: key,
                    value: value,
                    deviceRepository: deviceRepository,
                    groupRepository: groupRepository,
                    gatewayClient: gatewayClient
                )
            },
            sleep: { try await Task.sleep(for: $0) }
        )
    }
}

extension EnvironmentValues {
    @Entry var lightStoreDependencies: LightStore.Dependencies =
        LightStoreDependencyFactory.make()
}

private struct LightFanOutCommand: Sendable, Equatable {
    let identifier: DeviceIdentifier
    let key: String
    let value: PayloadValue
}

private func observeLightDescriptor(
    uniqueId: String,
    deviceRepository: DeviceRepository,
    groupRepository: GroupRepository
) async -> any AsyncSequence<DrivingLightControlDescriptor?, Never> & Sendable {
    if let identifier = DeviceIdentifier(storageKey: uniqueId) {
        return await deviceRepository
            .observeByID(identifier)
            .map { $0?.drivingLightControlDescriptor() }
            .removeDuplicates()
    }

    guard isLightGroupIdentifier(uniqueId) else {
        return AsyncStream<DrivingLightControlDescriptor?> { continuation in
            continuation.finish()
        }
        .removeDuplicates()
    }

    let groupStream = await groupRepository.observeByID(uniqueId)
    let devicesStream = await deviceRepository.observeAll()

    return combineLatest(groupStream, devicesStream)
        .map { group, devices in
            makeObservedGroupLightDescriptor(
                group: group,
                devices: devices
            )
        }
        .removeDuplicates()
}

private func applyOptimisticChanges(
    uniqueId: String,
    changes: [String: PayloadValue],
    deviceRepository: DeviceRepository,
    groupRepository: GroupRepository
) async {
    guard changes.isEmpty == false else { return }

    if let identifier = DeviceIdentifier(storageKey: uniqueId) {
        try? await applyOptimisticMemberChanges(
            [identifier: changes],
            deviceRepository: deviceRepository
        )
        return
    }

    guard isLightGroupIdentifier(uniqueId),
          let group = try? await groupRepository.get(uniqueId),
          group.resolvedUsage == .light else {
        return
    }

    let members = (try? await deviceRepository.listByIDs(group.memberIdentifiers)) ?? []
    let membersByIdentifier = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })
    let perMemberChanges = mapGroupOptimisticChanges(
        changes: changes,
        memberIdentifiers: group.memberIdentifiers,
        membersByIdentifier: membersByIdentifier
    )

    guard perMemberChanges.isEmpty == false else { return }
    try? await applyOptimisticMemberChanges(
        perMemberChanges,
        deviceRepository: deviceRepository
    )
}

private func sendLightCommand(
    uniqueId: String,
    key: String,
    value: PayloadValue,
    deviceRepository: DeviceRepository,
    groupRepository: GroupRepository,
    gatewayClient: DeltaDoreClient
) async {
    if let identifier = DeviceIdentifier(storageKey: uniqueId) {
        let request = makeLightCommand(
            deviceId: identifier.deviceId,
            endpointId: identifier.endpointId,
            key: key,
            value: value
        )
        try? await gatewayClient.send(text: request.request)
        return
    }

    guard isLightGroupIdentifier(uniqueId) else { return }

    let fanOutCommands = await mapGroupCommands(
        groupId: uniqueId,
        key: key,
        value: value,
        deviceRepository: deviceRepository,
        groupRepository: groupRepository
    )

    for command in fanOutCommands {
        let request = makeLightCommand(
            deviceId: command.identifier.deviceId,
            endpointId: command.identifier.endpointId,
            key: command.key,
            value: command.value
        )
        try? await gatewayClient.send(text: request.request)
    }
}

private func mapGroupCommands(
    groupId: String,
    key: String,
    value: PayloadValue,
    deviceRepository: DeviceRepository,
    groupRepository: GroupRepository
) async -> [LightFanOutCommand] {
    guard let group = try? await groupRepository.get(groupId),
          group.resolvedUsage == .light else {
        return []
    }

    let memberIdentifiers = group.memberIdentifiers.uniquePreservingOrder()
    guard memberIdentifiers.isEmpty == false else { return [] }

    let members = (try? await deviceRepository.listByIDs(memberIdentifiers)) ?? []
    let membersByIdentifier = Dictionary(uniqueKeysWithValues: members.map { ($0.id, $0) })

    return memberIdentifiers.flatMap { identifier in
        let descriptor = membersByIdentifier[identifier]?.drivingLightControlDescriptor()
        return mapGroupControlCommand(
            identifier: identifier,
            descriptor: descriptor,
            key: key,
            value: value
        )
    }
}

private func mapGroupOptimisticChanges(
    changes: [String: PayloadValue],
    memberIdentifiers: [DeviceIdentifier],
    membersByIdentifier: [DeviceIdentifier: Device]
) -> [DeviceIdentifier: [String: PayloadValue]] {
    var mapped: [DeviceIdentifier: [String: PayloadValue]] = [:]

    for identifier in memberIdentifiers.uniquePreservingOrder() {
        let descriptor = membersByIdentifier[identifier]?.drivingLightControlDescriptor()
        var memberChanges: [String: PayloadValue] = [:]

        for (key, value) in changes {
            let fanOut = mapGroupControlCommand(
                identifier: identifier,
                descriptor: descriptor,
                key: key,
                value: value
            )

            for command in fanOut where command.identifier == identifier {
                memberChanges[command.key] = command.value
            }
        }

        if memberChanges.isEmpty == false {
            mapped[identifier] = memberChanges
        }
    }

    return mapped
}

private func applyOptimisticMemberChanges(
    _ perMemberChanges: [DeviceIdentifier: [String: PayloadValue]],
    deviceRepository: DeviceRepository
) async throws {
    let identifiers = Array(perMemberChanges.keys)
    guard identifiers.isEmpty == false else { return }

    try await deviceRepository.mutateByIDs(identifiers) { device in
        guard let changes = perMemberChanges[device.id] else { return }
        for (key, value) in changes {
            device.data[key] = JSONValue(deltaDore: value)
        }
    }
}

private func makeObservedGroupLightDescriptor(
    group: Group?,
    devices: [Device]
) -> DrivingLightControlDescriptor? {
    guard let group, group.resolvedUsage == .light else { return nil }

    let devicesByIdentifier = Dictionary(uniqueKeysWithValues: devices.map { ($0.id, $0) })
    let memberDescriptors = group.memberIdentifiers.compactMap { identifier in
        devicesByIdentifier[identifier]?.drivingLightControlDescriptor()
    }

    guard memberDescriptors.isEmpty == false else { return nil }

    let maxNormalized = memberDescriptors.reduce(0.0) { partial, descriptor in
        max(partial, descriptor.normalizedLevel)
    }
    let level = min(max(maxNormalized, 0), 1) * 100

    return DrivingLightControlDescriptor(
        powerKey: "on",
        levelKey: "level",
        isOn: maxNormalized > 0.01,
        level: level,
        range: 0...100
    )
}

private func mapGroupControlCommand(
    identifier: DeviceIdentifier,
    descriptor: DrivingLightControlDescriptor?,
    key: String,
    value: PayloadValue
) -> [LightFanOutCommand] {
    guard let descriptor else {
        return [
            .init(
                identifier: identifier,
                key: key,
                value: value
            )
        ]
    }

    if key == "on" {
        let desiredOn = value.boolValue ?? ((value.numberValue ?? 0) > 0.01)

        if let powerKey = descriptor.powerKey {
            return [
                .init(
                    identifier: identifier,
                    key: powerKey,
                    value: .bool(desiredOn)
                )
            ]
        }

        if let levelKey = descriptor.levelKey {
            let target = desiredOn ? descriptor.range.upperBound : descriptor.range.lowerBound
            return [
                .init(
                    identifier: identifier,
                    key: levelKey,
                    value: .number(target)
                )
            ]
        }

        return [
            .init(
                identifier: identifier,
                key: key,
                value: .bool(desiredOn)
            )
        ]
    }

    if key == "level" {
        let normalized = normalizedValueForGroupControl(value)
        let desiredOn = normalized > 0.01

        var commands: [LightFanOutCommand] = []
        if let levelKey = descriptor.levelKey {
            let target = descriptor.range.lowerBound
                + (descriptor.range.upperBound - descriptor.range.lowerBound) * normalized
            commands.append(
                .init(
                    identifier: identifier,
                    key: levelKey,
                    value: .number(target)
                )
            )

            if let powerKey = descriptor.powerKey {
                commands.append(
                    .init(
                        identifier: identifier,
                        key: powerKey,
                        value: .bool(desiredOn)
                    )
                )
            }

            return commands
        }

        if let powerKey = descriptor.powerKey {
            return [
                .init(
                    identifier: identifier,
                    key: powerKey,
                    value: .bool(desiredOn)
                )
            ]
        }

        return [
            .init(
                identifier: identifier,
                key: key,
                value: .number(normalized * 100)
            )
        ]
    }

    return [
        .init(
            identifier: identifier,
            key: key,
            value: value
        )
    ]
}

private nonisolated func normalizedValueForGroupControl(_ value: PayloadValue) -> Double {
    if let boolValue = value.boolValue {
        return boolValue ? 1 : 0
    }
    if let number = value.numberValue {
        if number > 1 {
            return min(max(number / 100, 0), 1)
        }
        return min(max(number, 0), 1)
    }
    if let string = value.stringValue, let number = Double(string) {
        if number > 1 {
            return min(max(number / 100, 0), 1)
        }
        return min(max(number, 0), 1)
    }
    return 0
}

private nonisolated func makeLightCommand(
    deviceId: Int,
    endpointId: Int,
    key: String,
    value: PayloadValue
) -> TydomCommand {
    let transactionId = TydomCommand.defaultTransactionId()
    return TydomCommand.putDevicesData(
        deviceId: String(deviceId),
        endpointId: String(endpointId),
        name: key,
        value: lightCommandValue(from: value),
        transactionId: transactionId
    )
}

private nonisolated func lightCommandValue(from value: PayloadValue) -> TydomCommand.DeviceDataValue {
    switch value {
    case .bool(let flag):
        return .bool(flag)
    case .number(let number):
        return .int(Int(number.rounded()))
    case .string(let text):
        return .string(text)
    case .null, .object, .array:
        return .null
    }
}

nonisolated func isLightGroupIdentifier(_ uniqueId: String) -> Bool {
    Int(uniqueId) != nil
}
