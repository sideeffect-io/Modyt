import Foundation

struct TydomMessageHydratorDependencies: Sendable {
    let deviceInfo: @Sendable (String) async -> TydomDeviceInfo?
    let scenarioMetadata: @Sendable (Int) async -> TydomScenarioMetadata?
    let applyCacheMutation: @Sendable (TydomCacheMutation) async -> Void
    let log: @Sendable (String) -> Void

    init(
        deviceInfo: @escaping @Sendable (String) async -> TydomDeviceInfo?,
        scenarioMetadata: @escaping @Sendable (Int) async -> TydomScenarioMetadata?,
        applyCacheMutation: @escaping @Sendable (TydomCacheMutation) async -> Void,
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) {
        self.deviceInfo = deviceInfo
        self.scenarioMetadata = scenarioMetadata
        self.applyCacheMutation = applyCacheMutation
        self.log = log
    }
}

struct TydomMessageHydrator: Sendable {
    private let dependencies: TydomMessageHydratorDependencies

    init(dependencies: TydomMessageHydratorDependencies) {
        self.dependencies = dependencies
    }

    func hydrate(_ decoded: TydomDecodedEnvelope) async -> TydomHydratedEnvelope {
        let metadata = decoded.metadata

        for mutation in decoded.cacheMutations {
            await dependencies.applyCacheMutation(mutation)
        }

        switch decoded.payload {
        case .gatewayInfo(let info):
            return TydomHydratedEnvelope(
                message: .gatewayInfo(info, metadata: metadata),
                effects: decoded.effects
            )
        case .deviceUpdates(let updates):
            let result = await hydrateDeviceUpdates(
                from: updates,
                transactionId: metadata.transactionId
            )
            let devices = result.devices
            let extraEffects = result.effects
            if devices.isEmpty {
                return TydomHydratedEnvelope(
                    message: .raw(metadata),
                    effects: decoded.effects + extraEffects
                )
            }
            return TydomHydratedEnvelope(
                message: .devices(devices, metadata: metadata),
                effects: decoded.effects + extraEffects
            )
        case .devicesMeta(let entries):
            return TydomHydratedEnvelope(
                message: .devicesMeta(entries, metadata: metadata),
                effects: decoded.effects
            )
        case .devicesCMeta(let entries):
            return TydomHydratedEnvelope(
                message: .devicesCMeta(entries, metadata: metadata),
                effects: decoded.effects
            )
        case .scenarios(let payloads):
            let scenarios = await hydrateScenarios(from: payloads)
            return TydomHydratedEnvelope(
                message: .scenarios(scenarios, metadata: metadata),
                effects: decoded.effects
            )
        case .groupMetadata(let groupMetadata):
            return TydomHydratedEnvelope(
                message: .groupMetadata(groupMetadata, metadata: decoded.metadata),
                effects: decoded.effects
            )
        case .groups(let groups):
            return TydomHydratedEnvelope(
                message: .groups(groups, metadata: metadata),
                effects: decoded.effects
            )
        case .moments(let moments):
            return TydomHydratedEnvelope(
                message: .moments(moments, metadata: metadata),
                effects: decoded.effects
            )
        case .areas(let areas):
            return TydomHydratedEnvelope(
                message: .areas(areas, metadata: metadata),
                effects: decoded.effects
            )
        case .areasMeta(let entries):
            return TydomHydratedEnvelope(
                message: .areasMeta(entries, metadata: metadata),
                effects: decoded.effects
            )
        case .areasCMeta(let entries):
            return TydomHydratedEnvelope(
                message: .areasCMeta(entries, metadata: metadata),
                effects: decoded.effects
            )
        case .ack(let ack):
            return TydomHydratedEnvelope(
                message: .ack(ack, metadata: metadata),
                effects: decoded.effects
            )
        case .none:
            return TydomHydratedEnvelope(message: .raw(metadata), effects: decoded.effects)
        }
    }

    private func hydrateDeviceUpdates(
        from updates: [TydomDeviceUpdate],
        transactionId: String?
    ) async -> (devices: [TydomDevice], effects: [TydomMessageEffect]) {
        var devices: [TydomDevice] = []
        var effects: [TydomMessageEffect] = []
        var missingInfo = 0
        var skippedCData = 0
        var emptyData = 0
        var missingInfoSamples: [String] = []
        for update in updates {
            guard let info = await dependencies.deviceInfo(update.uniqueId) else {
                missingInfo += 1
                if missingInfoSamples.count < 5 {
                    missingInfoSamples.append(update.uniqueId)
                }
                continue
            }
            if update.source == .cdata {
                if info.usage == "alarm" {
                    if let transactionId, let entries = update.cdataEntries, entries.isEmpty == false {
                        let done = entries.contains { entry in
                            entry.objectValue?["EOR"]?.boolValue == true
                        }
                        effects.append(.cdataReplyChunk(TydomCDataReplyChunk(
                            transactionId: transactionId,
                            events: entries,
                            done: done
                        )))
                    }
                    skippedCData += 1
                    continue
                }
                if info.usage != "conso" {
                    skippedCData += 1
                    continue
                }
                if update.data.isEmpty {
                    emptyData += 1
                    continue
                }
            }
            if update.data.isEmpty {
                emptyData += 1
            }
            if isShutterUsage(info.usage), let traceValue = tracePositionValue(in: update.data) {
                dependencies.log(
                    "ShutterTrace hydrator uniqueId=\(update.uniqueId) usage=\(info.usage) source=\(update.source) tx=\(transactionId ?? "nil") position=\(traceValue)"
                )
            }
            devices.append(TydomDevice(
                id: update.id,
                endpointId: update.endpointId,
                uniqueId: update.uniqueId,
                name: info.name,
                usage: info.usage,
                kind: TydomDeviceKind.fromUsage(info.usage),
                data: update.data,
                entries: update.entries,
                metadata: info.metadata ?? update.metadata
            ))
        }
        dependencies.log(
            "Hydrate device updates total=\(updates.count) devices=\(devices.count) missingInfo=\(missingInfo) skippedCData=\(skippedCData) emptyData=\(emptyData) missingInfoSample=\(missingInfoSamples)"
        )
        return (devices, effects)
    }

    private func isShutterUsage(_ usage: String) -> Bool {
        usage == "shutter"
            || usage == "klineShutter"
            || usage == "awning"
            || usage == "swingShutter"
    }

    private func tracePositionValue(in data: [String: JSONValue]) -> String? {
        if let position = data["position"] {
            return position.traceString
        }
        if let level = data["level"] {
            return level.traceString
        }
        return nil
    }

    private func hydrateScenarios(from payloads: [TydomScenarioPayload]) async -> [TydomScenario] {
        var scenarios: [TydomScenario] = []
        for payload in payloads {
            let metadata = await dependencies.scenarioMetadata(payload.id)
            let name = metadata?.name ?? payload.payload["name"]?.stringValue ?? "Scenario \(payload.id)"
            let type = metadata?.type ?? payload.payload["type"]?.stringValue ?? "NORMAL"
            let picto = metadata?.picto ?? payload.payload["picto"]?.stringValue ?? ""
            let ruleId = metadata?.ruleId ?? payload.payload["rule_id"]?.stringValue
            scenarios.append(TydomScenario(
                id: payload.id,
                name: name,
                type: type,
                picto: picto,
                ruleId: ruleId,
                payload: payload.payload
            ))
        }
        return scenarios
    }
}


struct TydomHydratedEnvelope: Sendable, Equatable {
    let message: TydomMessage
    let effects: [TydomMessageEffect]

    init(message: TydomMessage, effects: [TydomMessageEffect] = []) {
        self.message = message
        self.effects = effects
    }
}

private extension JSONValue {
    var traceString: String {
        switch self {
        case .string(let text):
            return "\"\(text)\""
        case .number(let number):
            if number.rounded(.towardZero) == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .object(let value):
            return "object(keys:\(value.keys.sorted()))"
        case .array(let value):
            return "array(count:\(value.count))"
        case .null:
            return "null"
        }
    }
}
