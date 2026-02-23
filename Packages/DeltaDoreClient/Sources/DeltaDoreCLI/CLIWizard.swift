import Foundation
import DeltaDoreClient

actor CLIInputReader {
    private var bufferedLines: [String] = []
    private var waiters: [CheckedContinuation<String?, Never>] = []
    private var finished = false

    init(stream: AsyncStream<String>) {
        Task {
            for await line in stream {
                await self.push(line)
            }
            await self.finish()
        }
    }

    func nextLine() async -> String? {
        if bufferedLines.isEmpty == false {
            return bufferedLines.removeFirst()
        }
        if finished {
            return nil
        }
        return await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    private func push(_ line: String) {
        if waiters.isEmpty == false {
            let waiter = waiters.removeFirst()
            waiter.resume(returning: line)
            return
        }
        bufferedLines.append(line)
    }

    private func finish() {
        finished = true
        let pendingWaiters = waiters
        waiters.removeAll(keepingCapacity: false)
        for waiter in pendingWaiters {
            waiter.resume(returning: nil)
        }
    }
}

struct CLIGatewaySnapshot: Sendable {
    let devices: [CLIWizardDeviceTarget]
    let groups: [CLIWizardGroupTarget]
    let scenes: [CLIWizardSceneTarget]
}

struct CLIWizardDeviceTarget: Sendable {
    let deviceId: Int
    let endpointId: Int
    let name: String?
    let usage: String?
    let dataNames: [String]

    var menuLabel: String {
        let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Device \(deviceId)"
        let usageText = usage.flatMap { $0.isEmpty ? nil : $0 }.map { " - \($0)" } ?? ""
        return "\(title) (device \(deviceId), endpoint \(endpointId)\(usageText))"
    }
}

struct CLIWizardGroupTarget: Sendable {
    let members: [CLIWizardGroupMember]
    let id: Int
    let name: String?
    let usage: String?

    var menuLabel: String {
        let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Group \(id)"
        let usageText = usage.flatMap { $0.isEmpty ? nil : $0 }.map { " - \($0)" } ?? ""
        return "\(title) (id \(id)\(usageText))"
    }
}

struct CLIWizardGroupMember: Sendable, Hashable {
    let deviceId: Int
    let endpointId: Int
}

struct CLIWizardSceneTarget: Sendable {
    let id: Int
    let name: String?

    var menuLabel: String {
        let title = name.flatMap { $0.isEmpty ? nil : $0 } ?? "Scene \(id)"
        return "\(title) (id \(id))"
    }
}

struct CLIPreloadProgress: Sendable {
    let configsFileReceived: Bool
    let devicesDataReceived: Bool
    let groupsFileReceived: Bool
    let scenariosFileReceived: Bool

    var isComplete: Bool {
        configsFileReceived
            && devicesDataReceived
            && groupsFileReceived
            && scenariosFileReceived
    }

    var missingPaths: [String] {
        var paths: [String] = []
        if configsFileReceived == false {
            paths.append("/configs/file")
        }
        if devicesDataReceived == false {
            paths.append("/devices/data")
        }
        if groupsFileReceived == false {
            paths.append("/groups/file")
        }
        if scenariosFileReceived == false {
            paths.append("/scenarios/file")
        }
        return paths
    }
}

actor CLIGatewayCatalog {
    private struct DeviceKey: Hashable, Sendable {
        let deviceId: Int
        let endpointId: Int
    }

    private struct MutableDevice: Sendable {
        let deviceId: Int
        let endpointId: Int
        var name: String?
        var usage: String?
        var dataNames: Set<String>
    }

    private struct MutableGroup: Sendable {
        let id: Int
        var members: Set<CLIWizardGroupMember>
        var name: String?
        var usage: String?
    }

    private struct MutableScene: Sendable {
        let id: Int
        var name: String?
    }

    private var devices: [DeviceKey: MutableDevice] = [:]
    private var groups: [Int: MutableGroup] = [:]
    private var scenes: [Int: MutableScene] = [:]
    private var currentRevision: Int = 0
    private var preloadFlags = PreloadFlags()

    private struct PreloadFlags: Sendable {
        var configsFileReceived = false
        var devicesDataReceived = false
        var groupsFileReceived = false
        var scenariosFileReceived = false
    }

    func ingest(_ message: TydomMessage) {
        var changed = false
        switch message {
        case .devices(let incomingDevices, _):
            changed = upsertDevices(from: incomingDevices)
        case .groups(let incomingGroups, _):
            changed = upsertGroups(from: incomingGroups)
        case .groupMetadata(let metadata, _):
            changed = upsertGroupMetadata(from: metadata)
        case .scenarios(let incomingScenes, _):
            changed = upsertScenes(from: incomingScenes)
        case .raw(let metadata):
            changed = ingest(raw: metadata.raw)
        case .gatewayInfo,
             .moments,
             .areas,
             .areasMeta,
             .areasCMeta,
             .devicesMeta,
             .devicesCMeta,
             .ack:
            break
        }

        if changed {
            currentRevision += 1
        }
    }

    func snapshot() -> CLIGatewaySnapshot {
        let deviceValues = devices.values
            .map { value in
                CLIWizardDeviceTarget(
                    deviceId: value.deviceId,
                    endpointId: value.endpointId,
                    name: value.name,
                    usage: value.usage,
                    dataNames: value.dataNames.sorted()
                )
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.name?.lowercased() ?? ""
                let rhsName = rhs.name?.lowercased() ?? ""
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
                if lhs.deviceId != rhs.deviceId {
                    return lhs.deviceId < rhs.deviceId
                }
                return lhs.endpointId < rhs.endpointId
            }

        let groupValues = groups.values
            .map { value in
                CLIWizardGroupTarget(
                    members: value.members.sorted { lhs, rhs in
                        if lhs.deviceId != rhs.deviceId {
                            return lhs.deviceId < rhs.deviceId
                        }
                        return lhs.endpointId < rhs.endpointId
                    },
                    id: value.id,
                    name: value.name,
                    usage: value.usage
                )
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.name?.lowercased() ?? ""
                let rhsName = rhs.name?.lowercased() ?? ""
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
                return lhs.id < rhs.id
            }

        let sceneValues = scenes.values
            .map { value in
                CLIWizardSceneTarget(id: value.id, name: value.name)
            }
            .sorted { lhs, rhs in
                let lhsName = lhs.name?.lowercased() ?? ""
                let rhsName = rhs.name?.lowercased() ?? ""
                if lhsName != rhsName {
                    return lhsName < rhsName
                }
                return lhs.id < rhs.id
            }

        return CLIGatewaySnapshot(devices: deviceValues, groups: groupValues, scenes: sceneValues)
    }

    func revision() -> Int {
        currentRevision
    }

    func resetPreloadTracking() {
        preloadFlags = PreloadFlags()
    }

    func preloadProgress() -> CLIPreloadProgress {
        CLIPreloadProgress(
            configsFileReceived: preloadFlags.configsFileReceived,
            devicesDataReceived: preloadFlags.devicesDataReceived,
            groupsFileReceived: preloadFlags.groupsFileReceived,
            scenariosFileReceived: preloadFlags.scenariosFileReceived
        )
    }

    private func upsertDevices(from incomingDevices: [TydomDevice]) -> Bool {
        var changed = false
        for device in incomingDevices {
            let key = DeviceKey(deviceId: device.id, endpointId: device.endpointId)
            let existing = devices[key]
            var entry = existing ?? MutableDevice(
                deviceId: device.id,
                endpointId: device.endpointId,
                name: nil,
                usage: nil,
                dataNames: []
            )
            if existing == nil {
                changed = true
            }
            if setIfChanged(&entry.name, to: normalizedString(device.name)) {
                changed = true
            }
            if setIfChanged(&entry.usage, to: normalizedString(device.usage)) {
                changed = true
            }
            for keyName in device.data.keys where keyName.isEmpty == false {
                if entry.dataNames.insert(keyName).inserted {
                    changed = true
                }
            }
            devices[key] = entry
        }
        return changed
    }

    private func upsertGroups(from incomingGroups: [TydomGroup]) -> Bool {
        var changed = false
        for group in incomingGroups {
            let existing = groups[group.id]
            var entry = existing ?? MutableGroup(id: group.id, members: [], name: nil, usage: nil)
            if existing == nil {
                changed = true
            }
            if let payload = group.payload["name"]?.stringValue {
                if setIfChanged(&entry.name, to: normalizedString(payload)) {
                    changed = true
                }
            }
            if let usage = group.payload["usage"]?.stringValue {
                if setIfChanged(&entry.usage, to: normalizedString(usage)) {
                    changed = true
                }
            }
            let groupMembers = groupMembers(from: group.devices)
            if upsertGroupMembers(groupMembers, into: &entry.members) {
                changed = true
            }
            groups[group.id] = entry
        }
        return changed
    }

    private func upsertGroupMetadata(from metadata: [TydomGroupMetadata]) -> Bool {
        var changed = false
        for group in metadata {
            let existing = groups[group.id]
            var entry = existing ?? MutableGroup(id: group.id, members: [], name: nil, usage: nil)
            if existing == nil {
                changed = true
            }
            if setIfChanged(&entry.name, to: normalizedString(group.name)) {
                changed = true
            }
            if setIfChanged(&entry.usage, to: normalizedString(group.usage)) {
                changed = true
            }
            groups[group.id] = entry
        }
        return changed
    }

    private func upsertScenes(from incomingScenes: [TydomScenario]) -> Bool {
        var changed = false
        for scene in incomingScenes {
            let existing = scenes[scene.id]
            var entry = existing ?? MutableScene(id: scene.id, name: nil)
            if existing == nil {
                changed = true
            }
            if setIfChanged(&entry.name, to: normalizedString(scene.name)) {
                changed = true
            }
            scenes[scene.id] = entry
        }
        return changed
    }

    private func ingest(raw: TydomRawMessage) -> Bool {
        guard let uri = raw.uriOrigin else {
            return false
        }
        let normalizedURI = normalizedPath(uri)
        markPreloadResponse(for: normalizedURI)

        guard let body = raw.frame?.body,
              body.isEmpty == false else {
            return false
        }

        var changed = false
        if normalizedURI == "/configs/file" {
            changed = ingestConfigsFile(body) || changed
        }
        if normalizedURI == "/groups/file" {
            changed = ingestGroupsFile(body) || changed
        }
        if normalizedURI == "/scenarios/file" {
            changed = ingestScenariosFile(body) || changed
        }
        if isDevicesDataPath(normalizedURI) {
            changed = ingestDevicesData(body, path: normalizedURI) || changed
        }

        return changed
    }

    private func ingestConfigsFile(_ data: Data) -> Bool {
        guard let payload = try? JSONDecoder().decode(WizardConfigsFilePayload.self, from: data) else {
            return false
        }

        var changed = false

        for endpoint in payload.endpoints {
            let key = DeviceKey(deviceId: endpoint.idDevice, endpointId: endpoint.idEndpoint)
            let existing = devices[key]
            var entry = existing ?? MutableDevice(
                deviceId: endpoint.idDevice,
                endpointId: endpoint.idEndpoint,
                name: nil,
                usage: nil,
                dataNames: []
            )
            if existing == nil {
                changed = true
            }
            if setIfChanged(&entry.name, to: normalizedString(endpoint.name)) {
                changed = true
            }
            if let usage = endpoint.lastUsage,
               setIfChanged(&entry.usage, to: normalizedString(usage)) {
                changed = true
            }
            devices[key] = entry
        }

        for group in payload.groups ?? [] {
            let existing = groups[group.id]
            var entry = existing ?? MutableGroup(id: group.id, members: [], name: nil, usage: nil)
            if existing == nil {
                changed = true
            }
            if let name = group.name,
               setIfChanged(&entry.name, to: normalizedString(name)) {
                changed = true
            }
            if let usage = group.usage,
               setIfChanged(&entry.usage, to: normalizedString(usage)) {
                changed = true
            }
            groups[group.id] = entry
        }

        for scene in payload.scenarios ?? [] {
            let existing = scenes[scene.id]
            var entry = existing ?? MutableScene(id: scene.id, name: nil)
            if existing == nil {
                changed = true
            }
            if let name = scene.name,
               setIfChanged(&entry.name, to: normalizedString(name)) {
                changed = true
            }
            scenes[scene.id] = entry
        }

        return changed
    }

    private func ingestGroupsFile(_ data: Data) -> Bool {
        guard let payload = try? JSONDecoder().decode(JSONValue.self, from: data) else {
            return false
        }
        guard let values = extractGroupValues(from: payload) else {
            return false
        }

        var changed = false
        for value in values {
            guard let object = value.objectValue else { continue }
            let source = object["payload"]?.objectValue ?? object
            guard let id = intValue(source["id"]) else { continue }
            let existing = groups[id]
            var entry = existing ?? MutableGroup(id: id, members: [], name: nil, usage: nil)
            if existing == nil {
                changed = true
            }
            if let name = source["name"]?.stringValue,
               setIfChanged(&entry.name, to: normalizedString(name)) {
                changed = true
            }
            if let usage = source["usage"]?.stringValue,
               setIfChanged(&entry.usage, to: normalizedString(usage)) {
                changed = true
            }
            let members = groupMembers(from: source)
            if upsertGroupMembers(members, into: &entry.members) {
                changed = true
            }
            groups[id] = entry
        }

        return changed
    }

    private func ingestScenariosFile(_ data: Data) -> Bool {
        guard let payload = try? JSONDecoder().decode([String: JSONValue].self, from: data),
              let values = payload["scn"]?.arrayValue else {
            return false
        }

        var changed = false
        for value in values {
            guard let object = value.objectValue,
                  let id = intValue(object["id"]) else {
                continue
            }
            let existing = scenes[id]
            var entry = existing ?? MutableScene(id: id, name: nil)
            if existing == nil {
                changed = true
            }
            if let name = object["name"]?.stringValue,
               setIfChanged(&entry.name, to: normalizedString(name)) {
                changed = true
            }
            scenes[id] = entry
        }

        return changed
    }

    private func ingestDevicesData(_ data: Data, path: String) -> Bool {
        if let payload = decodeArrayOrSingle(WizardDevicesDataPayload.self, from: data) {
            var changed = false
            for device in payload {
                for endpoint in device.endpoints {
                    if upsertDeviceData(deviceId: device.id, endpointId: endpoint.id, dataEntries: endpoint.data ?? []) {
                        changed = true
                    }
                }
            }
            return changed
        }

        if let ids = parseDeviceEndpointIds(from: path),
           let endpointPayload = try? JSONDecoder().decode(WizardDeviceEndpointDataPayload.self, from: data) {
            return upsertDeviceData(deviceId: ids.deviceId, endpointId: ids.endpointId, dataEntries: endpointPayload.data ?? [])
        }

        return false
    }

    private func upsertDeviceData(
        deviceId: Int,
        endpointId: Int,
        dataEntries: [WizardDevicesDataPayload.Entry]
    ) -> Bool {
        let key = DeviceKey(deviceId: deviceId, endpointId: endpointId)
        let existing = devices[key]
        var entry = existing ?? MutableDevice(
            deviceId: deviceId,
            endpointId: endpointId,
            name: nil,
            usage: nil,
            dataNames: []
        )

        var changed = existing == nil
        for dataEntry in dataEntries where dataEntry.name.isEmpty == false {
            if entry.dataNames.insert(dataEntry.name).inserted {
                changed = true
            }
        }

        devices[key] = entry
        return changed
    }

    private func setIfChanged(_ value: inout String?, to newValue: String?) -> Bool {
        guard value != newValue else { return false }
        value = newValue
        return true
    }

    private func normalizedString(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private func extractGroupValues(from payload: JSONValue) -> [JSONValue]? {
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

    private func intValue(_ value: JSONValue?) -> Int? {
        if let number = value?.numberValue {
            return Int(number.rounded())
        }
        if let string = value?.stringValue {
            return Int(string)
        }
        return nil
    }

    private func groupMembers(from devices: [TydomGroup.DeviceMember]) -> [CLIWizardGroupMember] {
        var members: [CLIWizardGroupMember] = []
        for device in devices {
            if device.endpoints.isEmpty {
                members.append(CLIWizardGroupMember(deviceId: device.id, endpointId: device.id))
                continue
            }
            for endpoint in device.endpoints {
                members.append(CLIWizardGroupMember(deviceId: device.id, endpointId: endpoint.id))
            }
        }
        return members
    }

    private func groupMembers(from source: [String: JSONValue]) -> [CLIWizardGroupMember] {
        guard let devices = source["devices"]?.arrayValue else {
            return []
        }

        var members: [CLIWizardGroupMember] = []
        for deviceValue in devices {
            guard let deviceObject = deviceValue.objectValue,
                  let deviceId = intValue(deviceObject["id"]) else {
                continue
            }

            let endpoints = deviceObject["endpoints"]?.arrayValue ?? []
            if endpoints.isEmpty {
                members.append(CLIWizardGroupMember(deviceId: deviceId, endpointId: deviceId))
                continue
            }

            for endpointValue in endpoints {
                guard let endpointObject = endpointValue.objectValue,
                      let endpointId = intValue(endpointObject["id"]) else {
                    continue
                }
                members.append(CLIWizardGroupMember(deviceId: deviceId, endpointId: endpointId))
            }
        }

        return members
    }

    private func upsertGroupMembers(
        _ groupMembers: [CLIWizardGroupMember],
        into currentMembers: inout Set<CLIWizardGroupMember>
    ) -> Bool {
        var changed = false
        for member in groupMembers {
            if currentMembers.insert(member).inserted {
                changed = true
            }
        }
        return changed
    }

    private func isDevicesDataPath(_ path: String) -> Bool {
        if path == "/devices/data" {
            return true
        }
        return path.contains("/devices/") && path.contains("/data")
    }

    private func markPreloadResponse(for uri: String) {
        if uri == "/configs/file" {
            preloadFlags.configsFileReceived = true
            return
        }
        if uri == "/groups/file" {
            preloadFlags.groupsFileReceived = true
            return
        }
        if uri == "/scenarios/file" {
            preloadFlags.scenariosFileReceived = true
            return
        }
        if uri == "/devices/data" {
            preloadFlags.devicesDataReceived = true
        }
    }

    private func parseDeviceEndpointIds(from path: String) -> (deviceId: Int, endpointId: Int)? {
        let normalized = normalizedPath(path)
        let components = normalized.split(separator: "/").map(String.init)
        guard components.count == 5 else { return nil }
        guard components[0] == "devices" else { return nil }
        guard components[2] == "endpoints" else { return nil }
        guard components[4] == "data" else { return nil }
        guard let deviceId = Int(components[1]) else { return nil }
        guard let endpointId = Int(components[3]) else { return nil }
        return (deviceId, endpointId)
    }

    private func normalizedPath(_ path: String) -> String {
        path
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
            .first
            .map(String.init) ?? path
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
}

private struct WizardConfigsFilePayload: Decodable {
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
    }

    struct GroupMetadata: Decodable {
        let id: Int
        let name: String?
        let usage: String?
    }
}

private struct WizardDevicesDataPayload: Decodable {
    let id: Int
    let endpoints: [Endpoint]

    struct Endpoint: Decodable {
        let id: Int
        let data: [Entry]?
    }

    struct Entry: Decodable {
        let name: String
    }
}

private struct WizardDeviceEndpointDataPayload: Decodable {
    let data: [WizardDevicesDataPayload.Entry]?
}

private enum CLIWizardAction: CaseIterable {
    case ping
    case info
    case refreshAll
    case getLocalClaim
    case getGeoloc
    case putApiMode
    case updateFirmware
    case getDevicesMeta
    case getDevices
    case listDevices
    case readDeviceData
    case getDeviceData
    case pollDevicePath
    case putDeviceData
    case getDevicesCmeta
    case getGroups
    case listGroups
    case putGroupData
    case getScenarios
    case listScenes
    case activateScene
    case getConfigs
    case putData
    case getAreasMeta
    case getAreasCmeta
    case getAreas
    case getMoments
    case alarmCData
    case ackEventsCData
    case historicCData

    var menuLabel: String {
        switch self {
        case .ping:
            return "Ping gateway"
        case .info:
            return "Fetch gateway info"
        case .refreshAll:
            return "Refresh all"
        case .getLocalClaim:
            return "Send GET /configs/gateway/local_claim"
        case .getGeoloc:
            return "Send GET /configs/gateway/geoloc"
        case .putApiMode:
            return "Send PUT /configs/gateway/api_mode"
        case .updateFirmware:
            return "Send PUT /configs/gateway/update"
        case .getDevicesMeta:
            return "Send GET /devices/meta"
        case .getDevices:
            return "Send GET /devices/data"
        case .listDevices:
            return "List pre-loaded devices"
        case .readDeviceData:
            return "Read one device endpoint data"
        case .getDeviceData:
            return "Send GET /devices/<id>/endpoints/<id>/data"
        case .pollDevicePath:
            return "Send GET custom polling path"
        case .putDeviceData:
            return "Set device endpoint value (PUT)"
        case .getDevicesCmeta:
            return "Send GET /devices/cmeta"
        case .getGroups:
            return "Send GET /groups/file"
        case .listGroups:
            return "List pre-loaded groups"
        case .putGroupData:
            return "Set group value (PUT)"
        case .getScenarios:
            return "Send GET /scenarios/file"
        case .listScenes:
            return "List pre-loaded scenes"
        case .activateScene:
            return "Activate scene"
        case .getConfigs:
            return "Send GET /configs/file"
        case .putData:
            return "Send generic PUT data command"
        case .getAreasMeta:
            return "Send GET /areas/meta"
        case .getAreasCmeta:
            return "Send GET /areas/cmeta"
        case .getAreas:
            return "Send GET /areas/data"
        case .getMoments:
            return "Send GET /moments/file"
        case .alarmCData:
            return "Send PUT alarm cdata command"
        case .ackEventsCData:
            return "Send PUT ackEventCmd cdata"
        case .historicCData:
            return "Send GET historic cdata"
        }
    }
}

private struct CLIWizardSelectedDevice {
    let deviceId: String
    let endpointId: String
    let dataNames: [String]
}

private struct CLIWizardSelectedGroup {
    let groupId: String
    let members: [CLIWizardGroupMember]
}

private struct CLIWizardOptionalInput {
    let value: String?
}

private let defaultDeviceFieldNameSuggestions: [String] = [
    "position",
    "level",
    "state",
    "open",
    "close",
    "stop",
    "on",
    "off"
]

private let defaultGroupFieldNameSuggestions: [String] = [
    "position",
    "level",
    "state",
    "command",
    "open",
    "close",
    "stop",
    "on",
    "off"
]

private enum CLIWizardValue {
    case string(String)
    case bool(Bool)
    case int(Int)
    case null

    func asPutDataValue() -> TydomCommand.PutDataValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .bool(let value):
            return .bool(value)
        case .int(let value):
            return .int(value)
        case .null:
            return .null
        }
    }

    func asDeviceDataValue() -> TydomCommand.DeviceDataValue {
        switch self {
        case .string(let value):
            return .string(value)
        case .bool(let value):
            return .bool(value)
        case .int(let value):
            return .int(value)
        case .null:
            return .null
        }
    }
}

func runWizard(
    connection: TydomConnection,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader,
    catalog: CLIGatewayCatalog,
    transactionIdGenerator: CLITransactionIDGenerator,
    frameLogger: CLIWebSocketFrameLogger? = nil
) async {
    await stdout.writeLine("Wizard mode. Enter 0 in menus, or `cancel` at prompts, to return.")

    while true {
        guard let actionIndex = await promptMenuChoice(
            title: "Choose an action:",
            options: CLIWizardAction.allCases.map(\.menuLabel),
            stdout: stdout,
            stderr: stderr,
            input: input
        ) else {
            await stdout.writeLine("Leaving wizard mode.")
            return
        }

        let action = CLIWizardAction.allCases[actionIndex]
        switch action {
        case .ping:
            _ = await sendWizardCommand(
                .ping(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .info:
            _ = await sendWizardCommand(
                .info(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .refreshAll:
            _ = await sendWizardCommand(
                .refreshAll(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getLocalClaim:
            _ = await sendWizardCommand(
                .localClaim(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getGeoloc:
            _ = await sendWizardCommand(
                .geoloc(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .putApiMode:
            _ = await sendWizardCommand(
                .apiMode(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .updateFirmware:
            _ = await sendWizardCommand(
                .updateFirmware(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getDevicesMeta:
            _ = await sendWizardCommand(
                .devicesMeta(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getDevices:
            _ = await sendWizardCommand(
                .devicesData(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .listDevices:
            await printKnownDevices(
                await catalog.snapshot().devices,
                stdout: stdout
            )
        case .readDeviceData:
            guard let selected = await chooseDeviceTarget(
                stdout: stdout,
                stderr: stderr,
                input: input,
                catalog: catalog
            ) else {
                continue
            }
            let path = "/devices/\(selected.deviceId)/endpoints/\(selected.endpointId)/data"
            _ = await sendWizardCommand(
                .pollDeviceData(url: path),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getDeviceData:
            guard let deviceId = await promptIntegerString(
                prompt: "Device ID (endpoint ID will match):",
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }
            _ = await sendWizardCommand(
                .deviceData(deviceId: deviceId),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .pollDevicePath:
            guard let path = await promptPathWithDefault(
                prompt: "Polling URL path",
                defaultValue: "/devices/1/endpoints/1/data",
                stdout: stdout,
                input: input
            ) else {
                continue
            }
            _ = await sendWizardCommand(
                .pollDeviceData(url: path),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .putDeviceData:
            guard let selected = await chooseDeviceTarget(
                stdout: stdout,
                stderr: stderr,
                input: input,
                catalog: catalog
            ) else {
                continue
            }
            guard let name = await chooseValueName(
                prompt: "Data field name:",
                suggestions: selected.dataNames,
                fallbackSuggestions: defaultDeviceFieldNameSuggestions,
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }
            guard let value = await promptWizardValue(
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }

            let command = TydomCommand.putDevicesData(
                deviceId: selected.deviceId,
                endpointId: selected.endpointId,
                name: name,
                value: value.asDeviceDataValue()
            )
            _ = await sendWizardCommand(
                command,
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getDevicesCmeta:
            _ = await sendWizardCommand(
                .devicesCmeta(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getGroups:
            _ = await sendWizardCommand(
                .groupsFile(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .listGroups:
            await printKnownGroups(
                await catalog.snapshot().groups,
                stdout: stdout
            )
        case .putGroupData:
            guard let selected = await chooseGroupTarget(
                stdout: stdout,
                stderr: stderr,
                input: input,
                catalog: catalog
            ) else {
                continue
            }

            guard selected.members.isEmpty == false else {
                await stderr.writeLine(
                    "Selected group \(selected.groupId) has no resolved members. Re-run preload or choose a discovered group."
                )
                continue
            }

            guard let fieldName = await chooseValueName(
                prompt: "Group field name:",
                suggestions: [],
                fallbackSuggestions: defaultGroupFieldNameSuggestions,
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }

            guard let value = await promptWizardValue(
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }

            for member in selected.members {
                let command = TydomCommand.putDevicesData(
                    deviceId: String(member.deviceId),
                    endpointId: String(member.endpointId),
                    name: fieldName,
                    value: value.asDeviceDataValue()
                )
                _ = await sendWizardCommand(
                    command,
                    connection: connection,
                    stdout: stdout,
                    stderr: stderr,
                    transactionIdGenerator: transactionIdGenerator,
                    frameLogger: frameLogger
                )
            }
        case .getScenarios:
            _ = await sendWizardCommand(
                .scenariosFile(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .listScenes:
            await printKnownScenes(
                await catalog.snapshot().scenes,
                stdout: stdout
            )
        case .activateScene:
            guard let sceneId = await chooseSceneTarget(
                stdout: stdout,
                stderr: stderr,
                input: input,
                catalog: catalog
            ) else {
                continue
            }
            _ = await sendWizardCommand(
                .activateScenario(sceneId),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getConfigs:
            _ = await sendWizardCommand(
                .configsFile(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .putData:
            guard let path = await promptPathWithDefault(
                prompt: "PUT path",
                defaultValue: "/configs/gateway/api_mode",
                stdout: stdout,
                input: input
            ) else {
                continue
            }
            guard let fieldName = await promptRequiredLine(
                prompt: "Field name:",
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }
            guard let value = await promptWizardValue(
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }
            _ = await sendWizardCommand(
                .putData(path: path, name: fieldName, value: value.asPutDataValue()),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getAreasMeta:
            _ = await sendWizardCommand(
                .areasMeta(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getAreasCmeta:
            _ = await sendWizardCommand(
                .areasCmeta(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getAreas:
            _ = await sendWizardCommand(
                .areasData(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .getMoments:
            _ = await sendWizardCommand(
                .momentsFile(),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .alarmCData:
            guard let selected = await chooseDeviceTarget(
                stdout: stdout,
                stderr: stderr,
                input: input,
                catalog: catalog
            ) else {
                continue
            }
            guard let alarmMode = await promptMenuChoice(
                title: "Alarm command variant:",
                options: [
                    "alarmCmd (no zone)",
                    "zoneCmd (zones payload)",
                    "partCmd (legacy zone splitting)"
                ],
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }
            guard let value = await promptRequiredLine(
                prompt: "Alarm value (ex: ON/OFF/ARM):",
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }
            guard let alarmPinInput = await promptOptionalLine(
                prompt: "Alarm PIN (optional):",
                stdout: stdout,
                input: input
            ) else {
                continue
            }
            let alarmPin = alarmPinInput.value

            let zoneId: String?
            let legacyZones: Bool
            switch alarmMode {
            case 0:
                zoneId = nil
                legacyZones = false
            case 1:
                guard let zoneInput = await promptOptionalLine(
                    prompt: "Zone ID/list (optional, ex: 1 or 1,2):",
                    stdout: stdout,
                    input: input
                ) else {
                    continue
                }
                zoneId = zoneInput.value
                legacyZones = false
            case 2:
                guard let zones = await promptRequiredLine(
                    prompt: "Legacy zone IDs (comma-separated):",
                    stdout: stdout,
                    stderr: stderr,
                    input: input
                ) else {
                    continue
                }
                zoneId = zones
                legacyZones = true
            default:
                continue
            }

            let commands = TydomCommand.alarmCData(
                deviceId: selected.deviceId,
                endpointId: selected.endpointId,
                alarmPin: alarmPin,
                value: value,
                zoneId: zoneId,
                legacyZones: legacyZones
            )
            if commands.isEmpty {
                await stderr.writeLine("No alarm command generated with provided values.")
                continue
            }
            for command in commands {
                _ = await sendWizardCommand(
                    command,
                    connection: connection,
                    stdout: stdout,
                    stderr: stderr,
                    transactionIdGenerator: transactionIdGenerator,
                    frameLogger: frameLogger
                )
            }
        case .ackEventsCData:
            guard let selected = await chooseDeviceTarget(
                stdout: stdout,
                stderr: stderr,
                input: input,
                catalog: catalog
            ) else {
                continue
            }
            guard let alarmPinInput = await promptOptionalLine(
                prompt: "Alarm PIN (optional):",
                stdout: stdout,
                input: input
            ) else {
                continue
            }
            let alarmPin = alarmPinInput.value
            _ = await sendWizardCommand(
                .ackEventsCData(
                    deviceId: selected.deviceId,
                    endpointId: selected.endpointId,
                    alarmPin: alarmPin
                ),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        case .historicCData:
            guard let selected = await chooseDeviceTarget(
                stdout: stdout,
                stderr: stderr,
                input: input,
                catalog: catalog
            ) else {
                continue
            }
            guard let eventTypeInput = await promptOptionalLine(
                prompt: "Historic event type (blank for ALL):",
                stdout: stdout,
                input: input
            ) else {
                continue
            }
            let eventType = eventTypeInput.value
            guard let indexStart = await promptIntegerWithDefault(
                prompt: "History index start",
                defaultValue: 0,
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }
            guard let elementCount = await promptIntegerWithDefault(
                prompt: "History element count",
                defaultValue: 10,
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                continue
            }
            _ = await sendWizardCommand(
                .historicCData(
                    deviceId: selected.deviceId,
                    endpointId: selected.endpointId,
                    eventType: eventType,
                    indexStart: indexStart,
                    nbElement: elementCount
                ),
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                transactionIdGenerator: transactionIdGenerator,
                frameLogger: frameLogger
            )
        }
    }
}

func preloadWizardCatalog(
    connection: TydomConnection,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    catalog: CLIGatewayCatalog,
    transactionIdGenerator: CLITransactionIDGenerator,
    frameLogger: CLIWebSocketFrameLogger? = nil
) async {
    await catalog.resetPreloadTracking()
    let commands: [TydomCommand] = [
        .configsFile(),
        .devicesData(),
        .groupsFile(),
        .scenariosFile()
    ]

    for command in commands {
        let sendSucceeded = await send(
            command: command,
            connection: connection,
            stdout: stdout,
            stderr: stderr,
            transactionIdGenerator: transactionIdGenerator,
            frameLogger: frameLogger
        )
        if sendSucceeded == false {
            return
        }
    }

    let progress = await waitForPreloadCompletion(catalog: catalog)
    if progress.isComplete == false {
        let missing = progress.missingPaths.joined(separator: ", ")
        await stderr.writeLine("Pre-load timed out waiting for: \(missing)")
    }

    let snapshot = await catalog.snapshot()
    await stdout.writeLine(
        "Pre-load complete: devices=\(snapshot.devices.count), groups=\(snapshot.groups.count), scenes=\(snapshot.scenes.count)."
    )
}

private func waitForPreloadCompletion(
    catalog: CLIGatewayCatalog,
    timeoutNanoseconds: UInt64 = 5_000_000_000
) async -> CLIPreloadProgress {
    let interval: UInt64 = 100_000_000
    var elapsed: UInt64 = 0

    while elapsed < timeoutNanoseconds {
        let progress = await catalog.preloadProgress()
        if progress.isComplete {
            return progress
        }
        try? await Task.sleep(nanoseconds: interval)
        elapsed += interval
    }

    return await catalog.preloadProgress()
}

private func printKnownDevices(
    _ devices: [CLIWizardDeviceTarget],
    stdout: ConsoleWriter
) async {
    guard devices.isEmpty == false else {
        await stdout.writeLine("Known devices: none (using pre-loaded catalog).")
        return
    }
    var lines: [String] = ["Known devices:"]
    for (index, device) in devices.enumerated() {
        lines.append("  [\(index + 1)] \(device.menuLabel)")
    }
    await stdout.writeLine(lines.joined(separator: "\n"))
}

private func printKnownGroups(
    _ groups: [CLIWizardGroupTarget],
    stdout: ConsoleWriter
) async {
    guard groups.isEmpty == false else {
        await stdout.writeLine("Known groups: none (using pre-loaded catalog).")
        return
    }
    var lines: [String] = ["Known groups:"]
    for (index, group) in groups.enumerated() {
        lines.append("  [\(index + 1)] \(group.menuLabel)")
    }
    await stdout.writeLine(lines.joined(separator: "\n"))
}

private func printKnownScenes(
    _ scenes: [CLIWizardSceneTarget],
    stdout: ConsoleWriter
) async {
    guard scenes.isEmpty == false else {
        await stdout.writeLine("Known scenes: none (using pre-loaded catalog).")
        return
    }
    var lines: [String] = ["Known scenes:"]
    for (index, scene) in scenes.enumerated() {
        lines.append("  [\(index + 1)] \(scene.menuLabel)")
    }
    await stdout.writeLine(lines.joined(separator: "\n"))
}

private func chooseDeviceTarget(
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader,
    catalog: CLIGatewayCatalog
) async -> CLIWizardSelectedDevice? {
    let snapshot = await catalog.snapshot()

    if snapshot.devices.isEmpty {
        await stdout.writeLine("No discovered devices yet. Enter IDs manually.")
        return await promptManualDeviceTarget(stdout: stdout, stderr: stderr, input: input)
    }

    var options = snapshot.devices.map(\.menuLabel)
    options.append("Enter device/endpoint IDs manually")

    guard let index = await promptMenuChoice(
        title: "Choose a device endpoint:",
        options: options,
        stdout: stdout,
        stderr: stderr,
        input: input
    ) else {
        return nil
    }

    if index == snapshot.devices.count {
        return await promptManualDeviceTarget(stdout: stdout, stderr: stderr, input: input)
    }

    let selected = snapshot.devices[index]
    return CLIWizardSelectedDevice(
        deviceId: String(selected.deviceId),
        endpointId: String(selected.endpointId),
        dataNames: selected.dataNames
    )
}

private func promptManualDeviceTarget(
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader
) async -> CLIWizardSelectedDevice? {
    guard let deviceId = await promptIntegerString(
        prompt: "Device ID:",
        stdout: stdout,
        stderr: stderr,
        input: input
    ) else {
        return nil
    }

    guard let endpointId = await promptIntegerString(
        prompt: "Endpoint ID:",
        stdout: stdout,
        stderr: stderr,
        input: input
    ) else {
        return nil
    }

    return CLIWizardSelectedDevice(deviceId: deviceId, endpointId: endpointId, dataNames: [])
}

private func chooseGroupTarget(
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader,
    catalog: CLIGatewayCatalog
) async -> CLIWizardSelectedGroup? {
    let snapshot = await catalog.snapshot()

        if snapshot.groups.isEmpty {
            await stdout.writeLine("No discovered groups yet. Enter a group ID manually.")
            guard let groupId = await promptIntegerString(
                prompt: "Group ID:",
                stdout: stdout,
                stderr: stderr,
                input: input
            ) else {
                return nil
            }
            return CLIWizardSelectedGroup(groupId: groupId, members: [])
        }

    var options = snapshot.groups.map(\.menuLabel)
    options.append("Enter group ID manually")

    guard let index = await promptMenuChoice(
        title: "Choose a group:",
        options: options,
        stdout: stdout,
        stderr: stderr,
        input: input
    ) else {
        return nil
    }

    if index == snapshot.groups.count {
        guard let groupId = await promptIntegerString(
            prompt: "Group ID:",
            stdout: stdout,
            stderr: stderr,
            input: input
        ) else {
            return nil
        }
        if let parsedGroupId = Int(groupId),
           let knownGroup = snapshot.groups.first(where: { $0.id == parsedGroupId }) {
            return CLIWizardSelectedGroup(groupId: groupId, members: knownGroup.members)
        }
        return CLIWizardSelectedGroup(groupId: groupId, members: [])
    }

    let selected = snapshot.groups[index]
    let groupId = String(selected.id)
    return CLIWizardSelectedGroup(groupId: groupId, members: selected.members)
}

private func chooseSceneTarget(
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader,
    catalog: CLIGatewayCatalog
) async -> String? {
    let snapshot = await catalog.snapshot()

    if snapshot.scenes.isEmpty {
        await stdout.writeLine("No discovered scenes yet. Enter a scene ID manually.")
        return await promptIntegerString(
            prompt: "Scene ID:",
            stdout: stdout,
            stderr: stderr,
            input: input
        )
    }

    var options = snapshot.scenes.map(\.menuLabel)
    options.append("Enter scene ID manually")

    guard let index = await promptMenuChoice(
        title: "Choose a scene:",
        options: options,
        stdout: stdout,
        stderr: stderr,
        input: input
    ) else {
        return nil
    }

    if index == snapshot.scenes.count {
        return await promptIntegerString(
            prompt: "Scene ID:",
            stdout: stdout,
            stderr: stderr,
            input: input
        )
    }

    return String(snapshot.scenes[index].id)
}

private func chooseValueName(
    prompt: String,
    suggestions: [String],
    fallbackSuggestions: [String] = [],
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader
) async -> String? {
    var seenNames = Set<String>()
    var options: [String] = []
    for suggestion in suggestions + fallbackSuggestions {
        let normalized = suggestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalized.isEmpty == false else { continue }
        let key = normalized.lowercased()
        if seenNames.insert(key).inserted {
            options.append(normalized)
        }
    }
    options.append("Enter custom name")

    guard let index = await promptMenuChoice(
        title: "Choose a field name:",
        options: options,
        stdout: stdout,
        stderr: stderr,
        input: input
    ) else {
        return nil
    }

    if index < options.count - 1 {
        return options[index]
    }

    return await promptRequiredLine(prompt: prompt, stdout: stdout, stderr: stderr, input: input)
}

private func promptWizardValue(
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader
) async -> CLIWizardValue? {
    let typeOptions = ["String", "Boolean", "Integer", "Null"]
    guard let selectedType = await promptMenuChoice(
        title: "Choose value type:",
        options: typeOptions,
        stdout: stdout,
        stderr: stderr,
        input: input
    ) else {
        return nil
    }

    switch selectedType {
    case 0:
        guard let value = await promptRequiredLine(
            prompt: "String value:",
            stdout: stdout,
            stderr: stderr,
            input: input
        ) else {
            return nil
        }
        return .string(value)
    case 1:
        guard let boolValue = await promptBoolean(stdout: stdout, stderr: stderr, input: input) else {
            return nil
        }
        return .bool(boolValue)
    case 2:
        guard let value = await promptIntegerString(
            prompt: "Integer value:",
            stdout: stdout,
            stderr: stderr,
            input: input
        ) else {
            return nil
        }
        guard let intValue = Int(value) else {
            return nil
        }
        return .int(intValue)
    case 3:
        return .null
    default:
        return nil
    }
}

private func promptBoolean(
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader
) async -> Bool? {
    guard let index = await promptMenuChoice(
        title: "Choose boolean value:",
        options: ["true", "false"],
        stdout: stdout,
        stderr: stderr,
        input: input
    ) else {
        return nil
    }
    return index == 0
}

private func promptPathWithDefault(
    prompt: String,
    defaultValue: String,
    stdout: ConsoleWriter,
    input: CLIInputReader
) async -> String? {
    let finalPrompt = "\(prompt) [default: \(defaultValue)]:"
    guard let line = await promptLine(prompt: finalPrompt, stdout: stdout, input: input) else {
        return nil
    }
    if isKeywordCancelInput(line) {
        return nil
    }
    return line.isEmpty ? defaultValue : line
}

private func promptOptionalLine(
    prompt: String,
    stdout: ConsoleWriter,
    input: CLIInputReader
) async -> CLIWizardOptionalInput? {
    guard let line = await promptLine(prompt: prompt, stdout: stdout, input: input) else {
        return nil
    }
    if isKeywordCancelInput(line) {
        return nil
    }
    return CLIWizardOptionalInput(value: line.isEmpty ? nil : line)
}

private func promptIntegerWithDefault(
    prompt: String,
    defaultValue: Int,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader
) async -> Int? {
    let finalPrompt = "\(prompt) [default: \(defaultValue)]:"

    while true {
        guard let line = await promptLine(prompt: finalPrompt, stdout: stdout, input: input) else {
            return nil
        }
        if isKeywordCancelInput(line) {
            return nil
        }
        if line.isEmpty {
            return defaultValue
        }
        guard let value = Int(line) else {
            await stderr.writeLine("Enter a numeric value.")
            continue
        }
        return value
    }
}

private func promptRequiredLine(
    prompt: String,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader
) async -> String? {
    while true {
        guard let line = await promptLine(prompt: prompt, stdout: stdout, input: input) else {
            return nil
        }
        if isKeywordCancelInput(line) {
            return nil
        }
        if line.isEmpty {
            await stderr.writeLine("Value is required.")
            continue
        }
        return line
    }
}

private func promptIntegerString(
    prompt: String,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader
) async -> String? {
    while true {
        guard let line = await promptLine(prompt: prompt, stdout: stdout, input: input) else {
            return nil
        }
        if isKeywordCancelInput(line) {
            return nil
        }
        guard let value = Int(line) else {
            await stderr.writeLine("Enter a numeric value.")
            continue
        }
        return String(value)
    }
}

private func promptMenuChoice(
    title: String,
    options: [String],
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    input: CLIInputReader
) async -> Int? {
    guard options.isEmpty == false else {
        return nil
    }

    await stdout.writeLine(title)
    for (index, option) in options.enumerated() {
        await stdout.writeLine("  [\(index + 1)] \(option)")
    }
    await stdout.writeLine("  [0] Cancel")

    while true {
        guard let line = await promptLine(prompt: "Selection:", stdout: stdout, input: input) else {
            return nil
        }
        if isCancelInput(line) {
            return nil
        }
        guard let value = Int(line), (1...options.count).contains(value) else {
            await stderr.writeLine("Invalid selection.")
            continue
        }
        return value - 1
    }
}

private func promptLine(
    prompt: String,
    stdout: ConsoleWriter,
    input: CLIInputReader
) async -> String? {
    await stdout.write("\(prompt) ")
    guard let line = await input.nextLine() else {
        return nil
    }
    return line.trimmingCharacters(in: .whitespacesAndNewlines)
}

private func isCancelInput(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "0" || isKeywordCancelInput(normalized)
}

private func isKeywordCancelInput(_ value: String) -> Bool {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    return normalized == "cancel"
        || normalized == "back"
        || normalized == "quit"
        || normalized == "q"
}

@discardableResult
private func sendWizardCommand(
    _ command: TydomCommand,
    connection: TydomConnection,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    transactionIdGenerator: CLITransactionIDGenerator,
    frameLogger: CLIWebSocketFrameLogger? = nil
) async -> Bool {
    let preparedRequest = await prepareRequestForSend(
        command.request,
        transactionIdGenerator: transactionIdGenerator
    )
    await stdout.writeLine("Generated command: \(preparedRequest.requestLine)")

    return await sendPreparedRequest(
        preparedRequest,
        connection: connection,
        stdout: stdout,
        stderr: stderr,
        frameLogger: frameLogger
    )
}
