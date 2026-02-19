import Foundation

struct TydomMessageHydratorDependencies: Sendable {
    let deviceInfo: @Sendable (String) async -> TydomDeviceInfo?
    let scenarioMetadata: @Sendable (Int) async -> TydomScenarioMetadata?
    let applyCacheMutation: @Sendable (TydomCacheMutation) async -> Void
    let log: @Sendable (String) -> Void
    let isPostPutPollingActive: @Sendable (String) async -> Bool

    init(
        deviceInfo: @escaping @Sendable (String) async -> TydomDeviceInfo?,
        scenarioMetadata: @escaping @Sendable (Int) async -> TydomScenarioMetadata?,
        applyCacheMutation: @escaping @Sendable (TydomCacheMutation) async -> Void,
        log: @escaping @Sendable (String) -> Void = { _ in },
        isPostPutPollingActive: @escaping @Sendable (String) async -> Bool = { _ in false }
    ) {
        self.deviceInfo = deviceInfo
        self.scenarioMetadata = scenarioMetadata
        self.applyCacheMutation = applyCacheMutation
        self.log = log
        self.isPostPutPollingActive = isPostPutPollingActive
    }
}

struct TydomMessageHydrator: Sendable {
    private let dependencies: TydomMessageHydratorDependencies

    init(dependencies: TydomMessageHydratorDependencies) {
        self.dependencies = dependencies
    }

    func hydrate(_ decoded: TydomDecodedEnvelope) async -> TydomHydratedEnvelope {
        for mutation in decoded.cacheMutations {
            await dependencies.applyCacheMutation(mutation)
        }

        switch decoded.payload {
        case .gatewayInfo(let info):
            return TydomHydratedEnvelope(
                message: .gatewayInfo(info, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .deviceUpdates(let updates):
            let result = await hydrateDeviceUpdates(
                from: updates,
                transactionId: decoded.raw.transactionId,
                uriOrigin: decoded.raw.uriOrigin
            )
            let devices = result.devices
            let extraEffects = result.effects
            if devices.isEmpty {
                return TydomHydratedEnvelope(
                    message: .raw(decoded.raw),
                    effects: decoded.effects + extraEffects
                )
            }
            return TydomHydratedEnvelope(
                message: .devices(devices, transactionId: decoded.raw.transactionId),
                effects: decoded.effects + extraEffects
            )
        case .scenarios(let payloads):
            let scenarios = await hydrateScenarios(from: payloads)
            return TydomHydratedEnvelope(
                message: .scenarios(scenarios, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .groupMetadata(let metadata):
            return TydomHydratedEnvelope(
                message: .groupMetadata(metadata, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .groups(let groups):
            return TydomHydratedEnvelope(
                message: .groups(groups, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .moments(let moments):
            return TydomHydratedEnvelope(
                message: .moments(moments, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .areas(let areas):
            return TydomHydratedEnvelope(
                message: .areas(areas, transactionId: decoded.raw.transactionId),
                effects: decoded.effects
            )
        case .echo(let echo):
            return TydomHydratedEnvelope(message: .echo(echo), effects: decoded.effects)
        case .none:
            return TydomHydratedEnvelope(message: .raw(decoded.raw), effects: decoded.effects)
        }
    }

    private func hydrateDeviceUpdates(
        from updates: [TydomDeviceUpdate],
        transactionId: String?,
        uriOrigin: String?
    ) async -> (devices: [TydomDevice], effects: [TydomMessageEffect]) {
        var devices: [TydomDevice] = []
        var effects: [TydomMessageEffect] = []
        var missingInfo = 0
        var skippedCData = 0
        var emptyData = 0
        var filteredByPolling = 0
        var missingInfoSamples: [String] = []
        let isBroadcastDevicesData = uriOrigin == "/devices/data"
        for update in updates {
            if isBroadcastDevicesData,
               update.source == .data,
               await dependencies.isPostPutPollingActive(update.uniqueId) {
                filteredByPolling += 1
                dependencies.log(
                    "Post-PUT filter drop uri=/devices/data tx=\(transactionId ?? "nil") uniqueId=\(update.uniqueId) reason=active-polling"
                )
                continue
            }

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
                metadata: info.metadata ?? update.metadata
            ))
        }
        dependencies.log(
            "Hydrate device updates total=\(updates.count) devices=\(devices.count) missingInfo=\(missingInfo) skippedCData=\(skippedCData) emptyData=\(emptyData) filteredByPolling=\(filteredByPolling) missingInfoSample=\(missingInfoSamples)"
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
