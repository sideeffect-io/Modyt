import Foundation
import DeltaDoreClient

private let suppressedStandardOutputPaths: Set<String> = [
    "/configs/file",
    "/groups/file",
    "/scenarios/file"
]

func shouldSuppressStandardOutputPath(_ path: String) -> Bool {
    let normalized = normalizePath(path)
    return suppressedStandardOutputPaths.contains(normalized)
}

func renderStandardOutputLines(
    message: TydomMessage,
    knownDevices: [CLIWizardDeviceTarget] = []
) -> [String] {
    let knownDeviceInfos = knownDeviceInfoMap(from: knownDevices)

    switch message {
    case .devices(let devices, let metadata):
        let tx = metadata.transactionId ?? "n/a"
        return devices.map { device in
            let key = DeviceEndpointKey(deviceId: device.id, endpointId: device.endpointId)
            let name = normalizedName(device.name) ?? knownDeviceInfos[key]?.name
            let source = deviceSourceLabel(deviceId: device.id, endpointId: device.endpointId, name: name)
            let value = primaryDeviceValueDescription(for: device)
            return "--->>> new data received: \(source) | \(value) | tx=\(tx)"
        }
    case .raw(let metadata):
        let raw = metadata.raw
        guard isPingRawMessage(raw) == false else {
            return []
        }
        guard let source = raw.uriOrigin else {
            return []
        }
        if shouldSuppressStandardOutputPath(source) {
            return []
        }
        guard isRawResponse(raw) else {
            return []
        }

        let value = rawValueDescription(raw)
        let tx = raw.transactionId ?? "n/a"

        if let deviceLines = deviceValueLinesFromRaw(
            raw,
            transactionId: tx,
            knownDeviceInfos: knownDeviceInfos
        ), deviceLines.isEmpty == false {
            return deviceLines
        }

        let renderedSource = displaySource(for: source, knownDeviceInfos: knownDeviceInfos)
        return ["--->>> new data received: \(renderedSource) | \(value) | tx=\(tx)"]
    case .gatewayInfo,
         .scenarios,
         .groupMetadata,
         .groups,
         .moments,
         .areas,
         .devicesMeta,
         .devicesCMeta,
         .areasMeta,
         .areasCMeta,
         .ack:
        return []
    }
}

func render(message: TydomMessage) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    let json = messageToJSONValue(message)
    guard let data = try? encoder.encode(json) else {
        return "{\"error\":\"Failed to encode message\"}"
    }
    return String(data: data, encoding: .utf8) ?? "{\"error\":\"Failed to encode message\"}"
}

private struct DeviceEndpointKey: Hashable {
    let deviceId: Int
    let endpointId: Int
}

private struct KnownDeviceInfo {
    let name: String?
    let usage: String?
}

private func knownDeviceInfoMap(from devices: [CLIWizardDeviceTarget]) -> [DeviceEndpointKey: KnownDeviceInfo] {
    var map: [DeviceEndpointKey: KnownDeviceInfo] = [:]
    for device in devices {
        map[DeviceEndpointKey(deviceId: device.deviceId, endpointId: device.endpointId)] = KnownDeviceInfo(
            name: normalizedName(device.name),
            usage: normalizedName(device.usage)
        )
    }
    return map
}

private func deviceSourceLabel(deviceId: Int, endpointId: Int, name: String?) -> String {
    let identifier = "device-\(deviceId)/endpoint-\(endpointId)"
    guard let name else {
        return identifier
    }
    return "\(identifier) (\(name))"
}

private func normalizedName(_ value: String?) -> String? {
    guard let value else {
        return nil
    }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

private func primaryDeviceValueDescription(for device: TydomDevice) -> String {
    let priorityKeys = preferredValueKeys(for: device)
    let data = device.data
    for key in priorityKeys {
        if let value = data[key] {
            return "\(key)=\(jsonValueText(value))"
        }
    }

    if let (key, value) = data.sorted(by: { lhs, rhs in lhs.key < rhs.key }).first {
        return "\(key)=\(jsonValueText(value))"
    }

    return "value=n/a"
}

private func preferredValueKeys(for device: TydomDevice) -> [String] {
    switch device.kind {
    case .light:
        return ["level", "position"]
    case .shutter:
        return ["position", "level"]
    default:
        return ["position", "level"]
    }
}

private func rawValueDescription(_ raw: TydomRawMessage) -> String {
    if let parseError = raw.parseError, parseError.isEmpty == false {
        return "parseError=\(parseError)"
    }

    if let frame = raw.frame {
        switch frame {
        case .response(let response):
            if let reason = response.reason, reason.isEmpty == false {
                return "status=\(response.status) \(reason)"
            }
            return "status=\(response.status)"
        case .request(let request):
            return "\(request.method) \(request.path)"
        }
    }

    if raw.payload.isEmpty {
        return "payload=empty"
    }
    return "payloadBytes=\(raw.payload.count)"
}

private func isRawResponse(_ raw: TydomRawMessage) -> Bool {
    guard let frame = raw.frame else {
        return false
    }
    if case .response = frame {
        return true
    }
    return false
}

private func deviceValueLinesFromRaw(
    _ raw: TydomRawMessage,
    transactionId: String,
    knownDeviceInfos: [DeviceEndpointKey: KnownDeviceInfo]
) -> [String]? {
    guard let uri = raw.uriOrigin,
          let frame = raw.frame,
          case .response(let response) = frame,
          let body = response.body else {
        return nil
    }

    if normalizePath(uri) == "/devices/data" {
        var payloads: [RawDevicesDataPayload] = decodeArrayOrSingle(RawDevicesDataPayload.self, from: body) ?? []
        if payloads.isEmpty {
            payloads = broadcastDevicesDataPayloadsFromRawPayload(raw.payload)
        }
        let lines: [String] = payloads.flatMap { payload in
            payload.endpoints.compactMap { endpoint -> String? in
                guard endpoint.error == nil || endpoint.error == 0 else {
                    return nil
                }
                let key = DeviceEndpointKey(deviceId: payload.id, endpointId: endpoint.id)
                let preferredKeys = preferredRawValueKeys(for: knownDeviceInfos[key]?.usage)
                let descriptor = rawDeviceValueDescription(entries: endpoint.data ?? [], preferredKeys: preferredKeys)
                let name = knownDeviceInfos[key]?.name
                let source = deviceSourceLabel(deviceId: payload.id, endpointId: endpoint.id, name: name)
                return "--->>> new data received: \(source) | \(descriptor) | tx=\(transactionId)"
            }
        }
        return lines
    }

    if let ids = parseDeviceEndpointIds(from: uri) {
        var entries = endpointDataEntries(from: body) ?? []
        if entries.isEmpty {
            entries = endpointDataEntriesFromRawPayload(raw.payload)
        }
        if entries.isEmpty {
            return nil
        }

        let key = DeviceEndpointKey(deviceId: ids.deviceId, endpointId: ids.endpointId)
        let preferredKeys = preferredRawValueKeys(for: knownDeviceInfos[key]?.usage)
        let descriptor = rawDeviceValueDescription(entries: entries, preferredKeys: preferredKeys)
        let name = knownDeviceInfos[key]?.name
        let source = deviceSourceLabel(deviceId: ids.deviceId, endpointId: ids.endpointId, name: name)
        let line = "--->>> new data received: \(source) | \(descriptor) | tx=\(transactionId)"
        return [line]
    }

    return nil
}

private func rawDeviceValueDescription(
    entries: [RawDevicesDataPayload.Entry],
    preferredKeys: [String]
) -> String {
    let validEntries = entries.filter { entry in
        guard let validity = entry.validity else {
            return true
        }
        return validity == "upToDate"
    }

    for key in preferredKeys {
        if let value = validEntries.first(where: { $0.name == key })?.value {
            return "\(key)=\(jsonValueText(value))"
        }
    }

    if let entry = validEntries.sorted(by: { $0.name < $1.name }).first,
       let value = entry.value {
        return "\(entry.name)=\(jsonValueText(value))"
    }

    return "value=n/a"
}

private func normalizePath(_ path: String) -> String {
    let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        .first
        .map(String.init) ?? trimmed
}

private func displaySource(
    for source: String,
    knownDeviceInfos: [DeviceEndpointKey: KnownDeviceInfo]
) -> String {
    guard let ids = parseDeviceEndpointIds(from: source) else {
        return source
    }
    let name = knownDeviceInfos[DeviceEndpointKey(deviceId: ids.deviceId, endpointId: ids.endpointId)]?.name
    return deviceSourceLabel(deviceId: ids.deviceId, endpointId: ids.endpointId, name: name)
}

private func preferredRawValueKeys(for usage: String?) -> [String] {
    let normalized = usage?.lowercased() ?? ""
    if normalized.contains("light") {
        return ["level", "position"]
    }
    if normalized.contains("shutter") || normalized.contains("blind") || normalized.contains("volet") {
        return ["position", "level"]
    }
    return ["position", "level"]
}

private func parseDeviceEndpointIds(from path: String) -> (deviceId: Int, endpointId: Int)? {
    let normalized = normalizePath(path)
    let components = normalized.split(separator: "/").map(String.init)
    guard components.count == 5 else { return nil }
    guard components[0] == "devices" else { return nil }
    guard components[2] == "endpoints" else { return nil }
    guard components[4] == "data" else { return nil }
    guard let deviceId = Int(components[1]) else { return nil }
    guard let endpointId = Int(components[3]) else { return nil }
    return (deviceId, endpointId)
}

private func decodeArrayOrSingle<T: Decodable>(_ type: T.Type, from data: Data) -> [T]? {
    let decoder = JSONDecoder()
    if let array = try? decoder.decode([T].self, from: data) {
        return array
    }
    if let single = try? decoder.decode(T.self, from: data) {
        return [single]
    }
    return nil
}

private func endpointDataEntries(from data: Data) -> [RawDevicesDataPayload.Entry]? {
    let decoder = JSONDecoder()

    if let payload = try? decoder.decode(RawDeviceEndpointDataPayload.self, from: data) {
        if let error = payload.error, error != 0 {
            return []
        }
        return payload.data ?? []
    }

    if let entries = try? decoder.decode([RawDevicesDataPayload.Entry].self, from: data) {
        return entries
    }

    if let entry = try? decoder.decode(RawDevicesDataPayload.Entry.self, from: data) {
        return [entry]
    }

    guard let value = try? decoder.decode(JSONValue.self, from: data) else {
        return nil
    }

    return extractEntries(from: value)
}

private func endpointDataEntriesFromRawPayload(_ payload: Data) -> [RawDevicesDataPayload.Entry] {
    for body in httpBodiesFromRawPayload(payload) {
        if let entries = endpointDataEntries(from: body), entries.isEmpty == false {
            return entries
        }
    }
    return []
}

private func broadcastDevicesDataPayloadsFromRawPayload(_ payload: Data) -> [RawDevicesDataPayload] {
    for body in httpBodiesFromRawPayload(payload) {
        if let payloads = decodeArrayOrSingle(RawDevicesDataPayload.self, from: body), payloads.isEmpty == false {
            return payloads
        }
    }
    return []
}

private func httpBodiesFromRawPayload(_ payload: Data) -> [Data] {
    let normalizedPayload = normalizedHTTPPayload(payload)
    let separator = Data([13, 10, 13, 10]) // \r\n\r\n
    let httpPrefix = Data("HTTP/".utf8)

    var bodies: [Data] = []
    var cursor = normalizedPayload.startIndex
    let end = normalizedPayload.endIndex

    while cursor < end {
        guard let headerRange = normalizedPayload.range(of: separator, options: [], in: cursor..<end) else {
            break
        }

        let headerData = normalizedPayload.subdata(in: cursor..<headerRange.lowerBound)
        let headers = parseHTTPHeaders(headerData)
        let bodyStart = headerRange.upperBound

        guard bodyStart <= end else {
            break
        }

        if let contentLength = headers["content-length"].flatMap(Int.init), contentLength >= 0 {
            let bodyEnd = min(bodyStart + contentLength, end)
            if bodyEnd > bodyStart {
                bodies.append(normalizedPayload.subdata(in: bodyStart..<bodyEnd))
            }
            cursor = bodyEnd
            continue
        }

        if let nextHeaderStart = normalizedPayload.range(of: httpPrefix, options: [], in: bodyStart..<end)?.lowerBound {
            if nextHeaderStart > bodyStart {
                bodies.append(normalizedPayload.subdata(in: bodyStart..<nextHeaderStart))
            }
            cursor = nextHeaderStart
        } else {
            if end > bodyStart {
                bodies.append(normalizedPayload.subdata(in: bodyStart..<end))
            }
            break
        }
    }

    return bodies
}

private func normalizedHTTPPayload(_ payload: Data) -> Data {
    let httpPrefix = Data("HTTP/".utf8)
    if payload.starts(with: httpPrefix) {
        return payload
    }
    if let range = payload.range(of: httpPrefix) {
        return payload.subdata(in: range.lowerBound..<payload.count)
    }
    return payload
}

private func parseHTTPHeaders(_ headerData: Data) -> [String: String] {
    let headerString = String(data: headerData, encoding: .isoLatin1) ?? String(decoding: headerData, as: UTF8.self)
    let lines = headerString.components(separatedBy: "\r\n")
    guard lines.isEmpty == false else {
        return [:]
    }

    var headers: [String: String] = [:]
    for line in lines.dropFirst() {
        guard let colonIndex = line.firstIndex(of: ":") else { continue }
        let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard key.isEmpty == false else { continue }
        headers[key] = value
    }
    return headers
}

private func extractEntries(from value: JSONValue) -> [RawDevicesDataPayload.Entry] {
    switch value {
    case .array(let array):
        var entries: [RawDevicesDataPayload.Entry] = []
        for item in array {
            entries.append(contentsOf: extractEntries(from: item))
        }
        return entries
    case .object(let object):
        if let error = intValue(from: object["error"]), error != 0 {
            return []
        }

        if let data = object["data"] {
            return extractEntries(from: data)
        }
        if let payload = object["payload"] {
            let payloadEntries = extractEntries(from: payload)
            if payloadEntries.isEmpty == false {
                return payloadEntries
            }
        }

        if let name = object["name"]?.stringValue {
            let entry = RawDevicesDataPayload.Entry(
                name: name,
                value: object["value"],
                validity: object["validity"]?.stringValue
            )
            return [entry]
        }

        if let values = object["values"]?.objectValue {
            return values.map { key, value in
                RawDevicesDataPayload.Entry(name: key, value: value, validity: nil)
            }
        }

        return []
    default:
        return []
    }
}

private func intValue(from value: JSONValue?) -> Int? {
    if let number = value?.numberValue {
        return Int(number.rounded())
    }
    if let string = value?.stringValue {
        return Int(string)
    }
    return nil
}

private func isPingRawMessage(_ raw: TydomRawMessage) -> Bool {
    if raw.uriOrigin == "/ping" {
        return true
    }

    guard let frame = raw.frame else {
        return false
    }

    switch frame {
    case .request(let request):
        return request.path == "/ping"
    case .response(let response):
        return response.headerValue("uri-origin") == "/ping"
    }
}

private struct RawDevicesDataPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let error: Int?
        let data: [Entry]?
    }

    struct Entry: Decodable {
        let name: String
        let value: JSONValue?
        let validity: String?
    }
}

private struct RawDeviceEndpointDataPayload: Decodable {
    let error: Int?
    let data: [RawDevicesDataPayload.Entry]?
}

private func jsonValueText(_ value: JSONValue) -> String {
    switch value {
    case .string(let text):
        return text
    case .number(let number):
        if number.rounded(.towardZero) == number {
            return String(Int(number))
        }
        return String(number)
    case .bool(let flag):
        return flag ? "true" : "false"
    case .null:
        return "null"
    case .object(let object):
        return "object(keys:\(object.keys.count))"
    case .array(let array):
        return "array(count:\(array.count))"
    }
}

private func messageToJSONValue(_ message: TydomMessage) -> JSONValue {
    switch message {
    case .gatewayInfo(let info, let metadata):
        return .object([
            "type": .string("gatewayInfo"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .object(info.payload)
        ])
    case .devices(let devices, let metadata):
        return .object([
            "type": .string("devices"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(devices.map(deviceToJSONValue))
        ])
    case .devicesMeta(let entries, let metadata):
        return .object([
            "type": .string("devicesMeta"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(entries.map(metadataEntryToJSONValue))
        ])
    case .devicesCMeta(let entries, let metadata):
        return .object([
            "type": .string("devicesCMeta"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(entries.map(metadataEntryToJSONValue))
        ])
    case .scenarios(let scenarios, let metadata):
        return .object([
            "type": .string("scenarios"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(scenarios.map(scenarioToJSONValue))
        ])
    case .groupMetadata(let groups, let metadata):
        return .object([
            "type": .string("groupMetadata"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(groups.map(groupMetadataToJSONValue))
        ])
    case .groups(let groups, let metadata):
        return .object([
            "type": .string("groups"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(groups.map(groupToJSONValue))
        ])
    case .moments(let moments, let metadata):
        return .object([
            "type": .string("moments"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(moments.map(momentToJSONValue))
        ])
    case .areas(let areas, let metadata):
        return .object([
            "type": .string("areas"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(areas.map(areaToJSONValue))
        ])
    case .areasMeta(let entries, let metadata):
        return .object([
            "type": .string("areasMeta"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(entries.map(metadataEntryToJSONValue))
        ])
    case .areasCMeta(let entries, let metadata):
        return .object([
            "type": .string("areasCMeta"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": .array(entries.map(metadataEntryToJSONValue))
        ])
    case .ack(let ack, let metadata):
        return .object([
            "type": .string("ack"),
            "transactionId": jsonOptionalString(metadata.transactionId),
            "metadata": messageMetadataToJSONValue(metadata),
            "payload": ackToJSONValue(ack)
        ])
    case .raw(let metadata):
        return messageMetadataToJSONValue(metadata)
    }
}

private func deviceToJSONValue(_ device: TydomDevice) -> JSONValue {
    var object: [String: JSONValue] = [
        "id": .number(Double(device.id)),
        "endpointId": .number(Double(device.endpointId)),
        "uniqueId": .string(device.uniqueId),
        "name": .string(device.name),
        "usage": .string(device.usage),
        "kind": .string(deviceKindString(device.kind)),
        "data": .object(device.data),
        "entries": .array(device.entries.map(deviceEntryToJSONValue))
    ]
    if let metadata = device.metadata {
        object["metadata"] = .object(metadata)
    } else {
        object["metadata"] = .null
    }
    return .object(object)
}

private func deviceEntryToJSONValue(_ entry: TydomDeviceDataEntry) -> JSONValue {
    .object([
        "name": .string(entry.name),
        "validity": jsonOptionalString(entry.validity),
        "value": entry.value,
        "payload": .object(entry.payload)
    ])
}

private func ackToJSONValue(_ ack: TydomAck) -> JSONValue {
    .object([
        "statusCode": .number(Double(ack.statusCode)),
        "reason": jsonOptionalString(ack.reason),
        "headers": jsonObject(from: ack.headers)
    ])
}

private func scenarioToJSONValue(_ scenario: TydomScenario) -> JSONValue {
    return .object([
        "id": .number(Double(scenario.id)),
        "name": .string(scenario.name),
        "type": .string(scenario.type),
        "picto": .string(scenario.picto),
        "ruleId": jsonOptionalString(scenario.ruleId),
        "payload": .object(scenario.payload)
    ])
}

private func groupMetadataToJSONValue(_ group: TydomGroupMetadata) -> JSONValue {
    return .object([
        "id": .number(Double(group.id)),
        "name": .string(group.name),
        "usage": .string(group.usage),
        "picto": jsonOptionalString(group.picto),
        "isGroupUser": .bool(group.isGroupUser),
        "isGroupAll": .bool(group.isGroupAll),
        "payload": .object(group.payload)
    ])
}

private func groupToJSONValue(_ group: TydomGroup) -> JSONValue {
    let devices = group.devices.map { device in
        JSONValue.object([
            "id": .number(Double(device.id)),
            "endpoints": .array(device.endpoints.map { endpoint in
                .object(["id": .number(Double(endpoint.id))])
            })
        ])
    }
    let areas = group.areas.map { area in
        JSONValue.object([
            "id": .number(Double(area.id))
        ])
    }
    return .object([
        "id": .number(Double(group.id)),
        "devices": .array(devices),
        "areas": .array(areas),
        "payload": .object(group.payload)
    ])
}

private func momentToJSONValue(_ moment: TydomMoment) -> JSONValue {
    return .object([
        "payload": .object(moment.payload)
    ])
}

private func areaToJSONValue(_ area: TydomArea) -> JSONValue {
    return .object([
        "id": area.id.map { .number(Double($0)) } ?? .null,
        "payload": .object(area.payload)
    ])
}

private func metadataEntryToJSONValue(_ entry: TydomMetadataEntry) -> JSONValue {
    return .object([
        "id": entry.id.map { .number(Double($0)) } ?? .null,
        "payload": .object(entry.payload)
    ])
}

private func messageMetadataToJSONValue(_ metadata: TydomMessageMetadata) -> JSONValue {
    let raw = metadata.raw
    var object: [String: JSONValue] = [
        "type": .string("raw"),
        "uriOrigin": jsonOptionalString(metadata.uriOrigin),
        "transactionId": jsonOptionalString(metadata.transactionId),
        "parseError": jsonOptionalString(raw.parseError),
        "bodyJSON": metadata.bodyJSON ?? .null
    ]

    let payload = stringForData(raw.payload)
    object["payload"] = .string(payload.value)
    object["payloadEncoding"] = .string(payload.encoding)

    if let body = metadata.body {
        let parsedBody = stringForData(body)
        object["body"] = .string(parsedBody.value)
        object["bodyEncoding"] = .string(parsedBody.encoding)
    } else {
        object["body"] = .null
    }

    if let frame = raw.frame {
        object["frame"] = httpFrameToJSONValue(frame)
    } else {
        object["frame"] = .null
    }
    return .object(object)
}

private func rawMessageToJSONValue(_ raw: TydomRawMessage) -> JSONValue {
    messageMetadataToJSONValue(TydomMessageMetadata(raw: raw))
}

private func httpFrameToJSONValue(_ frame: TydomHTTPFrame) -> JSONValue {
    switch frame {
    case .request(let request):
        var object: [String: JSONValue] = [
            "type": .string("request"),
            "method": .string(request.method),
            "path": .string(request.path),
            "headers": jsonObject(from: request.headers)
        ]
        if let body = request.body {
            let payload = stringForData(body)
            object["body"] = .string(payload.value)
            object["bodyEncoding"] = .string(payload.encoding)
        } else {
            object["body"] = .null
        }
        return .object(object)
    case .response(let response):
        var object: [String: JSONValue] = [
            "type": .string("response"),
            "status": .number(Double(response.status)),
            "reason": jsonOptionalString(response.reason),
            "headers": jsonObject(from: response.headers)
        ]
        if let body = response.body {
            let payload = stringForData(body)
            object["body"] = .string(payload.value)
            object["bodyEncoding"] = .string(payload.encoding)
        } else {
            object["body"] = .null
        }
        return .object(object)
    }
}

private func jsonObject(from headers: [String: String]) -> JSONValue {
    let mapped = headers.mapValues { JSONValue.string($0) }
    return .object(mapped)
}

private func jsonOptionalString(_ value: String?) -> JSONValue {
    guard let value else { return .null }
    return .string(value)
}

private func deviceKindString(_ kind: TydomDeviceKind) -> String {
    switch kind {
    case .shutter:
        return "shutter"
    case .window:
        return "window"
    case .door:
        return "door"
    case .garage:
        return "garage"
    case .gate:
        return "gate"
    case .light:
        return "light"
    case .energy:
        return "energy"
    case .smoke:
        return "smoke"
    case .boiler:
        return "boiler"
    case .alarm:
        return "alarm"
    case .weather:
        return "weather"
    case .water:
        return "water"
    case .thermo:
        return "thermo"
    case .other(let raw):
        return raw
    }
}

private func stringForData(_ data: Data) -> (value: String, encoding: String) {
    if let string = String(data: data, encoding: .utf8) {
        return (string, "utf8")
    }
    return (data.base64EncodedString(), "base64")
}
