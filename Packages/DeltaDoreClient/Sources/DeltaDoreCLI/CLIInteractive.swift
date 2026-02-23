import Foundation
import DeltaDoreClient

func parseInputCommand(_ line: String) -> Result<CLICommand, CLIParseError>? {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard trimmed.isEmpty == false else { return nil }

    if trimmed == "help" || trimmed == "?" {
        return .success(.help)
    }
    if trimmed == "wizard" || trimmed == "menu" {
        return .success(.wizard)
    }
    if trimmed == "quit" || trimmed == "exit" {
        return .success(.quit)
    }
    if trimmed.hasPrefix("raw ") {
        let raw = trimmed.dropFirst(4).trimmingCharacters(in: .whitespaces)
        guard raw.isEmpty == false else {
            return .failure(CLIParseError(message: "raw requires a request string."))
        }
        return .success(.sendRaw(String(raw)))
    }

    let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
    guard let command = parts.first?.lowercased() else { return nil }
    let args = Array(parts.dropFirst())

    switch command {
    case "ping":
        return .success(.send(.ping()))
    case "info":
        return .success(.send(.info()))
    case "refresh-all":
        return .success(.send(.refreshAll()))
    case "devices-meta":
        return .success(.send(.devicesMeta()))
    case "devices-data":
        return .success(.send(.devicesData()))
    case "configs-file":
        return .success(.send(.configsFile()))
    case "devices-cmeta":
        return .success(.send(.devicesCmeta()))
    case "areas-meta":
        return .success(.send(.areasMeta()))
    case "areas-cmeta":
        return .success(.send(.areasCmeta()))
    case "areas-data":
        return .success(.send(.areasData()))
    case "moments-file":
        return .success(.send(.momentsFile()))
    case "scenarios-file":
        return .success(.send(.scenariosFile()))
    case "groups-file":
        return .success(.send(.groupsFile()))
    case "api-mode":
        return .success(.send(.apiMode()))
    case "geoloc":
        return .success(.send(.geoloc()))
    case "local-claim":
        return .success(.send(.localClaim()))
    case "update-firmware":
        return .success(.send(.updateFirmware()))
    case "device-data":
        guard args.count == 1 else { return .failure(CLIParseError(message: "device-data <deviceId>")) }
        return .success(.send(.deviceData(deviceId: args[0])))
    case "poll-device":
        guard args.count == 1 else { return .failure(CLIParseError(message: "poll-device <url>")) }
        return .success(.send(.pollDeviceData(url: args[0])))
    case "activate-scenario":
        guard args.count == 1 else { return .failure(CLIParseError(message: "activate-scenario <scenarioId>")) }
        return .success(.send(.activateScenario(args[0])))
    case "set-active":
        guard args.count == 1, let value = parseBool(args[0]) else {
            return .failure(CLIParseError(message: "set-active <true|false>"))
        }
        return .success(.setActive(value))
    case "put-data":
        guard args.count >= 3 else {
            return .failure(CLIParseError(message: "put-data <path> <name> <value> [type]"))
        }
        let value = parsePutDataValue(value: args[2], typeHint: args.count > 3 ? args[3] : nil)
        return .success(.send(.putData(path: args[0], name: args[1], value: value)))
    case "put-devices-data":
        guard args.count >= 4 else {
            return .failure(CLIParseError(message: "put-devices-data <deviceId> <endpointId> <name> <value> [type]"))
        }
        let value = parseDeviceDataValue(value: args[3], typeHint: args.count > 4 ? args[4] : nil)
        return .success(.send(.putDevicesData(
            deviceId: args[0],
            endpointId: args[1],
            name: args[2],
            value: value
        )))
    case "alarm-cdata":
        guard (3...6).contains(args.count) else {
            return .failure(
                CLIParseError(
                    message: "alarm-cdata <deviceId> <endpointId> <value> [alarmPin|-] [zoneId|-] [legacyZones]"
                )
            )
        }
        let alarmPin = args.count > 3 ? parseOptionalCLIArgument(args[3]) : nil
        let zoneId = args.count > 4 ? parseOptionalCLIArgument(args[4]) : nil
        let legacyZones: Bool
        if args.count > 5 {
            guard let parsed = parseBool(args[5]) else {
                return .failure(CLIParseError(message: "legacyZones must be true or false."))
            }
            legacyZones = parsed
        } else {
            legacyZones = false
        }
        let commands = TydomCommand.alarmCData(
            deviceId: args[0],
            endpointId: args[1],
            alarmPin: alarmPin,
            value: args[2],
            zoneId: zoneId,
            legacyZones: legacyZones
        )
        guard commands.isEmpty == false else {
            return .failure(CLIParseError(message: "alarm-cdata produced no command. Provide zoneId when legacyZones is true."))
        }
        if commands.count == 1, let single = commands.first {
            return .success(.send(single))
        }
        return .success(.sendMany(commands))
    case "ack-events-cdata":
        guard (2...3).contains(args.count) else {
            return .failure(CLIParseError(message: "ack-events-cdata <deviceId> <endpointId> [alarmPin|-]"))
        }
        let alarmPin = args.count > 2 ? parseOptionalCLIArgument(args[2]) : nil
        return .success(.send(.ackEventsCData(
            deviceId: args[0],
            endpointId: args[1],
            alarmPin: alarmPin
        )))
    case "historic-cdata":
        guard (2...5).contains(args.count) else {
            return .failure(
                CLIParseError(message: "historic-cdata <deviceId> <endpointId> [eventType|-] [indexStart] [nbElement]")
            )
        }
        let eventType = args.count > 2 ? parseOptionalCLIArgument(args[2]) : nil
        let indexStart: Int
        if args.count > 3 {
            guard let parsed = Int(args[3]) else {
                return .failure(CLIParseError(message: "indexStart must be an integer."))
            }
            indexStart = parsed
        } else {
            indexStart = 0
        }
        let nbElement: Int
        if args.count > 4 {
            guard let parsed = Int(args[4]) else {
                return .failure(CLIParseError(message: "nbElement must be an integer."))
            }
            nbElement = parsed
        } else {
            nbElement = 10
        }
        return .success(.send(.historicCData(
            deviceId: args[0],
            endpointId: args[1],
            eventType: eventType,
            indexStart: indexStart,
            nbElement: nbElement
        )))
    default:
        return .failure(CLIParseError(message: "Unknown command: \(command). Type `help` for the list."))
    }
}

private func parsePutDataValue(value: String, typeHint: String?) -> TydomCommand.PutDataValue {
    if let typeHint {
        switch typeHint.lowercased() {
        case "null":
            return .null
        case "bool":
            return .bool(parseBool(value) ?? false)
        case "int":
            return .int(Int(value) ?? 0)
        default:
            return .string(value)
        }
    }

    if value.lowercased() == "null" { return .null }
    if let bool = parseBool(value) { return .bool(bool) }
    if let intValue = Int(value) { return .int(intValue) }
    return .string(value)
}

private func parseDeviceDataValue(value: String, typeHint: String?) -> TydomCommand.DeviceDataValue {
    if let typeHint {
        switch typeHint.lowercased() {
        case "null":
            return .null
        case "bool":
            return .bool(parseBool(value) ?? false)
        case "int":
            return .int(Int(value) ?? 0)
        default:
            return .string(value)
        }
    }

    if value.lowercased() == "null" { return .null }
    if let bool = parseBool(value) { return .bool(bool) }
    if let intValue = Int(value) { return .int(intValue) }
    return .string(value)
}

func commandHelpText() -> String {
    let entries: [(String, String)] = [
        ("help", "Show available commands"),
        ("wizard | menu", "Run guided command wizard (default mode)"),
        ("quit | exit", "Disconnect and quit"),
        ("set-active <true|false>", "Toggle app activity for polling"),
        ("ping", "GET /ping"),
        ("info", "GET /info"),
        ("refresh-all", "POST /refresh/all"),
        ("devices-meta", "GET /devices/meta"),
        ("devices-data", "GET /devices/data"),
        ("configs-file", "GET /configs/file"),
        ("devices-cmeta", "GET /devices/cmeta"),
        ("areas-meta", "GET /areas/meta"),
        ("areas-cmeta", "GET /areas/cmeta"),
        ("areas-data", "GET /areas/data"),
        ("moments-file", "GET /moments/file"),
        ("scenarios-file", "GET /scenarios/file"),
        ("groups-file", "GET /groups/file"),
        ("api-mode", "PUT /configs/gateway/api_mode"),
        ("geoloc", "GET /configs/gateway/geoloc"),
        ("local-claim", "GET /configs/gateway/local_claim"),
        ("update-firmware", "PUT /configs/gateway/update"),
        ("device-data <deviceId>", "GET /devices/<id>/endpoints/<id>/data"),
        ("poll-device <url>", "GET <url> (used by polling)"),
        ("activate-scenario <scenarioId>", "PUT /scenarios/<id>"),
        ("put-data <path> <name> <value> [type]", "PUT <path> with JSON body"),
        ("put-devices-data <deviceId> <endpointId> <name> <value> [type]", "PUT devices data"),
        ("alarm-cdata <deviceId> <endpointId> <value> [alarmPin|-] [zoneId|-] [legacyZones]", "PUT alarm/zone/part cdata"),
        ("ack-events-cdata <deviceId> <endpointId> [alarmPin|-]", "PUT ackEventCmd cdata"),
        ("historic-cdata <deviceId> <endpointId> [eventType|-] [indexStart] [nbElement]", "GET histo cdata"),
        ("raw <request>", "Send a raw HTTP request string")
    ]

    var lines: [String] = ["Commands:"]
    for (name, description) in entries {
        lines.append("  \(name) - \(description)")
    }
    return lines.joined(separator: "\n")
}

private func parseBool(_ value: String) -> Bool? {
    switch value.lowercased() {
    case "true", "1", "yes":
        return true
    case "false", "0", "no":
        return false
    default:
        return nil
    }
}

private func parseOptionalCLIArgument(_ value: String) -> String? {
    let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard normalized.isEmpty == false else {
        return nil
    }
    switch normalized.lowercased() {
    case "-", "none", "nil", "null":
        return nil
    default:
        return normalized
    }
}
