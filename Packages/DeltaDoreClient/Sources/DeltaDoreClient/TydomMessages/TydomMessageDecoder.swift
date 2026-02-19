import Foundation

struct TydomDeviceCacheEntry: Sendable, Equatable {
    let uniqueId: String
    var name: String?
    var usage: String?
    var metadata: [String: JSONValue]?

    init(
        uniqueId: String,
        name: String? = nil,
        usage: String? = nil,
        metadata: [String: JSONValue]? = nil
    ) {
        self.uniqueId = uniqueId
        self.name = name
        self.usage = usage
        self.metadata = metadata
    }
}

enum TydomMessageDecoder {
    static func decode(_ raw: TydomRawMessage) -> TydomDecodedEnvelope {
        guard raw.parseError == nil else {
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }
        guard let frame = raw.frame else {
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        let uriOrigin = raw.uriOrigin

        if uriOrigin == "/ping" {
            return TydomDecodedEnvelope(raw: raw, payload: .none, effects: [.pongReceived])
        }

        if let echo = decodeEchoMessage(raw: raw, frame: frame) {
            return TydomDecodedEnvelope(raw: raw, payload: .echo(echo))
        }

        guard let body = frame.body, body.isEmpty == false else {
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/info" {
            if let info = decodeGatewayInfo(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .gatewayInfo(info))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/configs/file" {
            if let result = decodeConfigsFile(body) {
                return TydomDecodedEnvelope(
                    raw: raw,
                    payload: .groupMetadata(result.groupMetadata),
                    cacheMutations: result.cacheMutations
                )
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/devices/meta" {
            if let mutations = decodeDevicesMeta(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .none, cacheMutations: mutations)
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/devices/cmeta" || uriOrigin == "/areas/cmeta" {
            if let result = decodeDevicesCMeta(body), result.urls.isEmpty == false || result.mutations.isEmpty == false {
                return TydomDecodedEnvelope(
                    raw: raw,
                    payload: .none,
                    cacheMutations: result.mutations,
                    effects: result.urls.isEmpty ? [] : [.schedulePoll(urls: result.urls, intervalSeconds: 10)]
                )
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if isDevicesData(uriOrigin) {
            if let updates = decodeDevicesData(body, uriOrigin: uriOrigin) {
                let withData = updates.filter { $0.data.isEmpty == false }.count
                DeltaDoreDebugLog.log(
                    "Decode devices data updates=\(updates.count) withData=\(withData)"
                )
                let positionUpdates = updates.compactMap { update -> String? in
                    guard let value = tracePositionValue(in: update.data) else { return nil }
                    return "\(update.uniqueId):\(value)"
                }
                if positionUpdates.isEmpty == false {
                    DeltaDoreDebugLog.log(
                        "ShutterTrace decoder uri=\(uriOrigin ?? "nil") tx=\(raw.transactionId ?? "nil") updates=\(positionUpdates.joined(separator: ","))"
                    )
                }
                return TydomDecodedEnvelope(raw: raw, payload: .deviceUpdates(updates))
            }
            DeltaDoreDebugLog.log(
                "Decode devices data failed bytes=\(body.count)"
            )
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if isDevicesCData(uriOrigin) {
            if let updates = decodeDevicesCData(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .deviceUpdates(updates))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/events" {
            return TydomDecodedEnvelope(raw: raw, payload: .none, effects: [.refreshAll])
        }

        if uriOrigin == "/groups/file" {
            if let groups = decodeGroupsFile(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .groups(groups))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/areas/data" {
            if let areas = decodeAreasData(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .areas(areas))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/moments/file" {
            if let moments = decodeMomentsFile(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .moments(moments))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        if uriOrigin == "/scenarios/file" {
            if let scenarios = decodeScenariosFile(body) {
                return TydomDecodedEnvelope(raw: raw, payload: .scenarios(scenarios))
            }
            return TydomDecodedEnvelope(raw: raw, payload: .none)
        }

        return TydomDecodedEnvelope(raw: raw, payload: .none)
    }

    private static func decodeEchoMessage(
        raw: TydomRawMessage,
        frame: TydomHTTPFrame
    ) -> TydomEchoMessage? {
        guard case .response(let response) = frame else { return nil }
        guard response.body?.isEmpty != false else { return nil }
        guard let uriOrigin = raw.uriOrigin, uriOrigin.isEmpty == false else { return nil }
        guard let transactionId = raw.transactionId, transactionId.isEmpty == false else { return nil }

        return TydomEchoMessage(
            uriOrigin: uriOrigin,
            transactionId: transactionId,
            statusCode: response.status,
            reason: response.reason,
            headers: response.headers
        )
    }

    private static func decodeGatewayInfo(_ data: Data) -> TydomGatewayInfo? {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data) else {
            return nil
        }
        return TydomGatewayInfo(payload: payload)
    }

    private static func decodeDevicesData(_ data: Data, uriOrigin: String?) -> [TydomDeviceUpdate]? {
        guard let payload = decodePayloadArray(DevicesDataPayload.self, from: data) else {
            return decodeDeviceEndpointData(data, uriOrigin: uriOrigin)
        }

        var updates: [TydomDeviceUpdate] = []
        for device in payload {
            for endpoint in device.endpoints {
                let uniqueId = "\(endpoint.id)_\(device.id)"
                let values = extractDataValues(from: endpoint)
                updates.append(TydomDeviceUpdate(
                    id: device.id,
                    endpointId: endpoint.id,
                    uniqueId: uniqueId,
                    data: values,
                    metadata: nil,
                    cdataEntries: nil,
                    source: .data
                ))
            }
        }
        if updates.isEmpty == false {
            return updates
        }

        return decodeDeviceEndpointData(data, uriOrigin: uriOrigin)
    }

    private static func extractDataValues(from endpoint: DevicesDataPayload.Endpoint) -> [String: JSONValue] {
        guard endpoint.error == nil || endpoint.error == 0 else { return [:] }
        var values: [String: JSONValue] = [:]
        if let entries = endpoint.data {
            for entry in entries {
                guard entry.validity == "upToDate", let value = entry.value else { continue }
                values[entry.name] = value
            }
        }

        if let link = endpoint.link, link.type == "area" {
            if let linkedAreaId = link.id {
                values["__linkedAreaId"] = .number(Double(linkedAreaId))
            }
            if let linkedAreaType = link.type {
                values["__linkedAreaType"] = .string(linkedAreaType)
            }
            if let linkedAreaSubtype = link.subtype {
                values["__linkedAreaSubtype"] = .string(linkedAreaSubtype)
            }
        }
        return values
    }

    private static func decodeDeviceEndpointData(_ data: Data, uriOrigin: String?) -> [TydomDeviceUpdate]? {
        guard let payload = try? JSONDecoder().decode(DeviceEndpointDataPayload.self, from: data) else {
            return nil
        }
        guard let ids = parseDeviceEndpointIds(from: uriOrigin) else {
            return nil
        }
        let endpoint = DevicesDataPayload.Endpoint(
            id: ids.endpointId,
            error: payload.error,
            data: payload.data,
            link: payload.link
        )
        let values = extractDataValues(from: endpoint)
        let update = TydomDeviceUpdate(
            id: ids.deviceId,
            endpointId: ids.endpointId,
            uniqueId: "\(ids.endpointId)_\(ids.deviceId)",
            data: values,
            metadata: nil,
            cdataEntries: nil,
            source: .data
        )
        return [update]
    }

    private static func decodeDevicesCData(_ data: Data) -> [TydomDeviceUpdate]? {
        guard let payload = decodePayloadArray(DevicesCDataPayload.self, from: data) else { return nil }

        var updates: [TydomDeviceUpdate] = []
        for device in payload {
            for endpoint in device.endpoints {
                guard endpoint.error == nil || endpoint.error == 0 else { continue }
                let uniqueId = "\(endpoint.id)_\(device.id)"
                let values = extractCDataValues(from: endpoint)
                let entries = endpoint.cdata ?? []
                let entryPayloads = entries.map { JSONValue.object($0.payload) }
                guard entryPayloads.isEmpty == false || values.isEmpty == false else { continue }

                updates.append(TydomDeviceUpdate(
                    id: device.id,
                    endpointId: endpoint.id,
                    uniqueId: uniqueId,
                    data: values,
                    metadata: nil,
                    cdataEntries: entryPayloads.isEmpty ? nil : entryPayloads,
                    source: .cdata
                ))
            }
        }
        return updates
    }

    private static func extractCDataValues(from endpoint: DevicesCDataPayload.Endpoint) -> [String: JSONValue] {
        guard let entries = endpoint.cdata else { return [:] }
        var values: [String: JSONValue] = [:]
        for entry in entries {
            if let dest = entry.parameters?["dest"]?.stringValue,
               let counter = entry.values?["counter"] {
                values["\(entry.name)_\(dest)"] = counter
                continue
            }

            if entry.parameters?["period"] != nil, let cdataValues = entry.values {
                for (key, value) in cdataValues where key.isUppercased {
                    values["\(entry.name)_\(key)"] = value
                }
            }
        }
        return values
    }

    private static func isDevicesData(_ path: String?) -> Bool {
        guard let path else { return false }
        if path == "/devices/data" { return true }
        return path.contains("/devices/") && path.contains("/data")
    }

    private static func parseDeviceEndpointIds(from path: String?) -> (deviceId: Int, endpointId: Int)? {
        guard let path else { return nil }
        let normalized = path
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? path
        let components = normalized.split(separator: "/").map(String.init)
        guard components.count == 5 else { return nil }
        guard components[0] == "devices" else { return nil }
        guard components[2] == "endpoints" else { return nil }
        guard components[4] == "data" else { return nil }
        guard let deviceId = Int(components[1]) else { return nil }
        guard let endpointId = Int(components[3]) else { return nil }
        return (deviceId, endpointId)
    }

    private static func isDevicesCData(_ path: String?) -> Bool {
        guard let path else { return false }
        if path == "/devices/cdata" { return true }
        return path.contains("/cdata")
    }

    private static func decodePayloadArray<T: Decodable>(_ type: T.Type, from data: Data) -> [T]? {
        let decoder = JSONDecoder()
        if let array = try? decoder.decode([T].self, from: data) { return array }
        if let single = try? decoder.decode(T.self, from: data) { return [single] }
        return nil
    }

    private static func tracePositionValue(in data: [String: JSONValue]) -> String? {
        if let position = data["position"] {
            return position.traceString
        }
        if let level = data["level"] {
            return level.traceString
        }
        return nil
    }

    private struct ConfigsFileDecodeResult {
        let cacheMutations: [TydomCacheMutation]
        let groupMetadata: [TydomGroupMetadata]
    }

    private static func decodeConfigsFile(_ data: Data) -> ConfigsFileDecodeResult? {
        guard let payload = try? JSONDecoder().decode(ConfigsFilePayload.self, from: data) else {
            return nil
        }

        var mutations: [TydomCacheMutation] = []
        for endpoint in payload.endpoints {
            let uniqueId = "\(endpoint.idEndpoint)_\(endpoint.idDevice)"
            let usage = endpoint.lastUsage ?? "unknown"
            let name = usage == "alarm" ? "Tyxal Alarm" : endpoint.name
            let entry = TydomDeviceCacheEntry(uniqueId: uniqueId, name: name, usage: usage, metadata: nil)
            mutations.append(.deviceEntry(entry))
        }

        if let scenarios = payload.scenarios {
            for scenario in scenarios {
                let metadata = TydomScenarioMetadata(
                    id: scenario.id,
                    name: scenario.name ?? "Scenario \(scenario.id)",
                    type: scenario.type ?? "NORMAL",
                    picto: scenario.picto ?? "",
                    ruleId: scenario.ruleId
                )
                mutations.append(.scenarioMetadata(metadata))
            }
        }

        let groupMetadata = (payload.groups ?? []).map { group in
            TydomGroupMetadata(
                id: group.id,
                name: group.name ?? "Group \(group.id)",
                usage: group.usage ?? "unknown",
                picto: group.picto,
                isGroupUser: group.isGroupUser ?? false,
                isGroupAll: group.isGroupAll ?? false,
                payload: group.payload
            )
        }

        return ConfigsFileDecodeResult(
            cacheMutations: mutations,
            groupMetadata: groupMetadata
        )
    }

    private static func decodeDevicesMeta(_ data: Data) -> [TydomCacheMutation]? {
        guard let payload = try? JSONDecoder().decode([DevicesMetaPayload].self, from: data) else {
            return nil
        }

        var mutations: [TydomCacheMutation] = []
        for device in payload {
            for endpoint in device.endpoints {
                let uniqueId = "\(endpoint.id)_\(device.id)"
                let metadata = (endpoint.metadata ?? []).reduce(into: [String: JSONValue]()) { acc, entry in
                    acc[entry.name] = .object(entry.attributes)
                }
                let entry = TydomDeviceCacheEntry(uniqueId: uniqueId, name: nil, usage: nil, metadata: metadata)
                mutations.append(.deviceEntry(entry))
            }
        }
        return mutations
    }

    private static func decodeDevicesCMeta(_ data: Data) -> (urls: [String], mutations: [TydomCacheMutation])? {
        guard let payload = try? JSONDecoder().decode([DevicesCMetaPayload].self, from: data) else {
            return nil
        }

        var urls: [String] = []
        var mutations: [TydomCacheMutation] = []
        let consoNames = Set(["energyIndex", "energyInstant", "energyDistrib", "energyHisto"])
        for device in payload {
            for endpoint in device.endpoints {
                let uniqueId = "\(endpoint.id)_\(device.id)"
                let cmetadataEntries = endpoint.cmetadata ?? []

                if cmetadataEntries.isEmpty == false {
                    let metadata: [String: JSONValue] = [
                        "__cmetadata": .array(
                            cmetadataEntries.map { .object($0.payload) }
                        )
                    ]
                    let entry = TydomDeviceCacheEntry(
                        uniqueId: uniqueId,
                        name: nil,
                        usage: nil,
                        metadata: metadata
                    )
                    mutations.append(.deviceEntry(entry))
                }

                for entry in cmetadataEntries {
                    if consoNames.contains(entry.name) {
                        let entry = TydomDeviceCacheEntry(uniqueId: uniqueId, name: "Tywatt", usage: "conso", metadata: nil)
                        mutations.append(.deviceEntry(entry))
                    }
                    switch entry.name {
                    case "energyIndex":
                        urls.append(contentsOf: urlsForCData(
                            deviceId: device.id,
                            endpointId: endpoint.id,
                            name: entry.name,
                            parameterName: "dest",
                            parameterValueKey: "dest",
                            parameters: entry.parameters ?? [],
                            suffix: "&reset=false"
                        ))
                    case "energyInstant":
                        urls.append(contentsOf: urlsForCData(
                            deviceId: device.id,
                            endpointId: endpoint.id,
                            name: entry.name,
                            parameterName: "unit",
                            parameterValueKey: "unit",
                            parameters: entry.parameters ?? [],
                            suffix: "&reset=false"
                        ))
                    case "energyHisto":
                        urls.append(contentsOf: urlsForCData(
                            deviceId: device.id,
                            endpointId: endpoint.id,
                            name: entry.name,
                            parameterName: "dest",
                            parameterValueKey: "dest",
                            parameters: entry.parameters ?? [],
                            suffix: "&period=YEAR&periodOffset=0"
                        ))
                    case "energyDistrib":
                        urls.append(contentsOf: urlsForCData(
                            deviceId: device.id,
                            endpointId: endpoint.id,
                            name: entry.name,
                            parameterName: "src",
                            parameterValueKey: "src",
                            parameters: entry.parameters ?? [],
                            suffix: "&period=YEAR&periodOffset=0"
                        ))
                    default:
                        continue
                    }
                }
            }
        }
        return (urls, mutations)
    }

    private static func urlsForCData(
        deviceId: Int,
        endpointId: Int,
        name: String,
        parameterName: String,
        parameterValueKey: String,
        parameters: [DevicesCMetaPayload.CMetaParameter],
        suffix: String
    ) -> [String] {
        let values = parameters.first(where: { $0.name == parameterName })?.enumValues ?? []
        return values.map { value in
            "/devices/\(deviceId)/endpoints/\(endpointId)/cdata?name=\(name)&\(parameterValueKey)=\(value)\(suffix)"
        }
    }

    private static func decodeGroupsFile(_ data: Data) -> [TydomGroup]? {
        guard let payload = try? JSONDecoder().decode(JSONValue.self, from: data) else { return nil }
        guard let groups = extractGroupValues(from: payload) else { return nil }
        return groups.compactMap(decodeGroupMembership(from:))
    }

    private static func decodeMomentsFile(_ data: Data) -> [TydomMoment]? {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        guard let moments = payload["moments"]?.arrayValue else { return [] }
        return moments.compactMap { value in
            value.objectValue.map { TydomMoment(payload: $0) }
        }
    }

    private static func decodeScenariosFile(_ data: Data) -> [TydomScenarioPayload]? {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data) else { return nil }
        guard let scenarios = payload["scn"]?.arrayValue else { return [] }
        return scenarios.compactMap { value in
            guard let object = value.objectValue else { return nil }
            guard let id = object["id"]?.numberValue.map(Int.init) else { return nil }
            return TydomScenarioPayload(id: id, payload: object)
        }
    }

    private static func decodeAreasData(_ data: Data) -> [TydomArea]? {
        if let array = try? JSONDecoder().decode([JSONValue].self, from: data) {
            return array.compactMap { value in
                guard let object = value.objectValue else { return nil }
                let id = object["id"]?.numberValue.map(Int.init)
                return TydomArea(id: id, payload: object)
            }
        }

        if let single = try? JSONDecoder().decode(JSONValue.self, from: data),
           let object = single.objectValue {
            let id = object["id"]?.numberValue.map(Int.init)
            return [TydomArea(id: id, payload: object)]
        }

        return nil
    }

    private static func extractGroupValues(from payload: JSONValue) -> [JSONValue]? {
        if let array = payload.arrayValue {
            return array
        }

        guard let object = payload.objectValue else { return nil }
        if let groups = object["groups"]?.arrayValue {
            return groups
        }
        if let wrapped = object["payload"]?.arrayValue {
            return wrapped
        }
        if let wrappedObject = object["payload"]?.objectValue {
            return [.object(wrappedObject)]
        }
        return []
    }

    private static func decodeGroupMembership(from value: JSONValue) -> TydomGroup? {
        guard let object = value.objectValue else { return nil }
        let payload = object["payload"]?.objectValue ?? object
        guard let id = intValue(from: payload["id"]) else { return nil }

        let devices = (payload["devices"]?.arrayValue ?? []).compactMap { value in
            decodeGroupDeviceMember(from: value)
        }
        let areas = (payload["areas"]?.arrayValue ?? []).compactMap { value in
            decodeGroupAreaMember(from: value)
        }

        return TydomGroup(
            id: id,
            devices: devices,
            areas: areas,
            payload: payload
        )
    }

    private static func decodeGroupDeviceMember(from value: JSONValue) -> TydomGroup.DeviceMember? {
        guard let object = value.objectValue else { return nil }
        guard let id = intValue(from: object["id"]) else { return nil }

        let endpoints: [TydomGroup.DeviceMember.EndpointMember] = (object["endpoints"]?.arrayValue ?? []).compactMap { value in
            guard let endpoint = value.objectValue else { return nil }
            guard let endpointId = intValue(from: endpoint["id"]) else { return nil }
            return TydomGroup.DeviceMember.EndpointMember(id: endpointId)
        }

        return TydomGroup.DeviceMember(id: id, endpoints: endpoints)
    }

    private static func decodeGroupAreaMember(from value: JSONValue) -> TydomGroup.AreaMember? {
        guard let object = value.objectValue else { return nil }
        guard let id = intValue(from: object["id"]) else { return nil }
        return TydomGroup.AreaMember(id: id)
    }

    private static func intValue(from value: JSONValue?) -> Int? {
        if let number = value?.numberValue {
            return Int(number.rounded())
        }
        if let string = value?.stringValue {
            return Int(string)
        }
        return nil
    }
}

private struct DevicesDataPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let error: Int?
        let data: [Entry]?
        let link: Link?
    }

    struct Link: Decodable {
        let type: String?
        let subtype: String?
        let id: Int?
    }

    struct Entry: Decodable {
        let name: String
        let value: JSONValue?
        let validity: String?
    }
}

private struct DeviceEndpointDataPayload: Decodable {
    let id: Int
    let error: Int?
    let data: [DevicesDataPayload.Entry]?
    let link: DevicesDataPayload.Link?
}

private struct DevicesCDataPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let error: Int?
        let cdata: [Entry]?
    }

    struct Entry: Decodable {
        let name: String
        let parameters: [String: JSONValue]?
        let values: [String: JSONValue]?
        let EOR: Bool?
        let payload: [String: JSONValue]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var payload: [String: JSONValue] = [:]
            for key in container.allKeys {
                payload[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
            }

            guard let nameValue = payload["name"]?.stringValue else {
                let context = DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing cdata name"
                )
                throw DecodingError.keyNotFound(DynamicCodingKey(stringValue: "name")!, context)
            }

            self.name = nameValue
            self.parameters = payload["parameters"]?.objectValue
            self.values = payload["values"]?.objectValue
            self.EOR = payload["EOR"]?.boolValue
            self.payload = payload
        }
    }
}

private extension String {
    var isUppercased: Bool {
        guard isEmpty == false else { return false }
        return self == uppercased()
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

private struct ConfigsFilePayload: Decodable {
    let endpoints: [Endpoint]
    let scenarios: [Scenario]?
    let groups: [GroupMetadata]?

    struct Endpoint: Decodable {
        let idEndpoint: Int
        let idDevice: Int
        let name: String
        let lastUsage: String?

        private enum CodingKeys: String, CodingKey {
            case idEndpoint = "id_endpoint"
            case idDevice = "id_device"
            case name
            case lastUsage = "last_usage"
        }
    }

    struct Scenario: Decodable {
        let id: Int
        let name: String?
        let type: String?
        let picto: String?
        let ruleId: String?

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case type
            case picto
            case ruleId = "rule_id"
        }
    }

    struct GroupMetadata: Decodable {
        let id: Int
        let name: String?
        let usage: String?
        let picto: String?
        let isGroupUser: Bool?
        let isGroupAll: Bool?
        let payload: [String: JSONValue]

        private enum CodingKeys: String, CodingKey {
            case id
            case name
            case usage
            case picto
            case isGroupUser = "is_group_user"
            case isGroupAll = "group_all"
        }

        init(from decoder: Decoder) throws {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            self.id = try keyed.decode(Int.self, forKey: .id)
            self.name = try keyed.decodeIfPresent(String.self, forKey: .name)
            self.usage = try keyed.decodeIfPresent(String.self, forKey: .usage)
            self.picto = try keyed.decodeIfPresent(String.self, forKey: .picto)
            self.isGroupUser = try keyed.decodeIfPresent(Bool.self, forKey: .isGroupUser)
            self.isGroupAll = try keyed.decodeIfPresent(Bool.self, forKey: .isGroupAll)

            let raw = try decoder.container(keyedBy: DynamicCodingKey.self)
            var payload: [String: JSONValue] = [:]
            for key in raw.allKeys {
                payload[key.stringValue] = try raw.decode(JSONValue.self, forKey: key)
            }
            self.payload = payload
        }
    }
}

private struct DevicesMetaPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let metadata: [MetadataEntry]?
    }

    struct MetadataEntry: Decodable {
        let name: String
        let attributes: [String: JSONValue]

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: DynamicCodingKey.self)
            var name: String?
            var attributes: [String: JSONValue] = [:]

            for key in container.allKeys {
                if key.stringValue == "name" {
                    name = try container.decode(String.self, forKey: key)
                } else {
                    attributes[key.stringValue] = try container.decode(JSONValue.self, forKey: key)
                }
            }

            guard let resolvedName = name else {
                let context = DecodingError.Context(
                    codingPath: container.codingPath,
                    debugDescription: "Missing metadata name"
                )
                throw DecodingError.keyNotFound(DynamicCodingKey(stringValue: "name")!, context)
            }

            self.name = resolvedName
            self.attributes = attributes
        }
    }
}

private struct DevicesCMetaPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let cmetadata: [CMetaEntry]?
    }

    struct CMetaEntry: Decodable {
        let name: String
        let parameters: [CMetaParameter]?
        let payload: [String: JSONValue]

        private enum CodingKeys: String, CodingKey {
            case name
            case parameters
        }

        init(from decoder: Decoder) throws {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try keyed.decode(String.self, forKey: .name)
            self.parameters = try keyed.decodeIfPresent([CMetaParameter].self, forKey: .parameters)

            let raw = try decoder.container(keyedBy: DynamicCodingKey.self)
            var payload: [String: JSONValue] = [:]
            for key in raw.allKeys {
                payload[key.stringValue] = try raw.decode(JSONValue.self, forKey: key)
            }
            self.payload = payload
        }
    }

    struct CMetaParameter: Decodable {
        let name: String
        let enumValues: [String]
        let payload: [String: JSONValue]

        private enum CodingKeys: String, CodingKey {
            case name
            case enumValues = "enum_values"
        }

        init(from decoder: Decoder) throws {
            let keyed = try decoder.container(keyedBy: CodingKeys.self)
            self.name = try keyed.decode(String.self, forKey: .name)
            self.enumValues = try keyed.decodeIfPresent([String].self, forKey: .enumValues) ?? []

            let raw = try decoder.container(keyedBy: DynamicCodingKey.self)
            var payload: [String: JSONValue] = [:]
            for key in raw.allKeys {
                payload[key.stringValue] = try raw.decode(JSONValue.self, forKey: key)
            }
            self.payload = payload
        }
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(intValue: Int) {
        self.stringValue = String(intValue)
        self.intValue = intValue
    }

    init?(stringValue: String) {
        self.stringValue = stringValue
        self.intValue = nil
    }
}
