import Foundation

public enum TydomMessage: Sendable, Equatable {
    case gatewayInfo(TydomGatewayInfo, metadata: TydomMessageMetadata)
    case devices([TydomDevice], metadata: TydomMessageMetadata)
    case devicesMeta([TydomMetadataEntry], metadata: TydomMessageMetadata)
    case devicesCMeta([TydomMetadataEntry], metadata: TydomMessageMetadata)
    case scenarios([TydomScenario], metadata: TydomMessageMetadata)
    case groupMetadata([TydomGroupMetadata], metadata: TydomMessageMetadata)
    case groups([TydomGroup], metadata: TydomMessageMetadata)
    case moments([TydomMoment], metadata: TydomMessageMetadata)
    case areas([TydomArea], metadata: TydomMessageMetadata)
    case areasMeta([TydomMetadataEntry], metadata: TydomMessageMetadata)
    case areasCMeta([TydomMetadataEntry], metadata: TydomMessageMetadata)
    case ack(TydomAck, metadata: TydomMessageMetadata)
    case raw(TydomMessageMetadata)

    public var metadata: TydomMessageMetadata {
        switch self {
        case .gatewayInfo(_, let metadata),
             .devices(_, let metadata),
             .devicesMeta(_, let metadata),
             .devicesCMeta(_, let metadata),
             .scenarios(_, let metadata),
             .groupMetadata(_, let metadata),
             .groups(_, let metadata),
             .moments(_, let metadata),
             .areas(_, let metadata),
             .areasMeta(_, let metadata),
             .areasCMeta(_, let metadata),
             .ack(_, let metadata):
            return metadata
        case .raw(let metadata):
            return metadata
        }
    }

    public var transactionId: String? {
        metadata.transactionId
    }
}

public struct TydomMessageMetadata: Sendable, Equatable {
    public let raw: TydomRawMessage
    public let uriOrigin: String?
    public let transactionId: String?
    public let body: Data?
    public let bodyJSON: JSONValue?

    public init(
        raw: TydomRawMessage,
        uriOrigin: String? = nil,
        transactionId: String? = nil,
        body: Data? = nil,
        bodyJSON: JSONValue? = nil
    ) {
        self.raw = raw
        self.uriOrigin = uriOrigin ?? raw.uriOrigin
        self.transactionId = transactionId ?? raw.transactionId
        self.body = body ?? raw.frame?.body
        self.bodyJSON = bodyJSON ?? Self.decodeBodyJSON(from: self.body)
    }

    private static func decodeBodyJSON(from data: Data?) -> JSONValue? {
        guard let data, data.isEmpty == false else { return nil }
        return try? JSONDecoder().decode(JSONValue.self, from: data)
    }
}

public struct TydomAck: Sendable, Equatable {
    public let statusCode: Int
    public let reason: String?
    public let headers: [String: String]

    public init(statusCode: Int, reason: String?, headers: [String: String]) {
        self.statusCode = statusCode
        self.reason = reason
        self.headers = headers
    }
}

public struct TydomRawMessage: Sendable, Equatable {
    public let payload: Data
    public let frame: TydomHTTPFrame?
    public let uriOrigin: String?
    public let transactionId: String?
    public let parseError: String?

    public init(
        payload: Data,
        frame: TydomHTTPFrame?,
        uriOrigin: String?,
        transactionId: String?,
        parseError: String?
    ) {
        self.payload = payload
        self.frame = frame
        self.uriOrigin = uriOrigin
        self.transactionId = transactionId
        self.parseError = parseError
    }
}

public struct TydomGatewayInfo: Sendable, Equatable {
    public let payload: [String: JSONValue]

    public init(payload: [String: JSONValue]) {
        self.payload = payload
    }
}

public struct TydomScenario: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let type: String
    public let picto: String
    public let ruleId: String?
    public let payload: [String: JSONValue]

    public init(
        id: Int,
        name: String,
        type: String,
        picto: String,
        ruleId: String?,
        payload: [String: JSONValue]
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.picto = picto
        self.ruleId = ruleId
        self.payload = payload
    }
}

public struct TydomGroupMetadata: Sendable, Equatable {
    public let id: Int
    public let name: String
    public let usage: String
    public let picto: String?
    public let isGroupUser: Bool
    public let isGroupAll: Bool
    public let payload: [String: JSONValue]

    public init(
        id: Int,
        name: String,
        usage: String,
        picto: String?,
        isGroupUser: Bool,
        isGroupAll: Bool,
        payload: [String: JSONValue]
    ) {
        self.id = id
        self.name = name
        self.usage = usage
        self.picto = picto
        self.isGroupUser = isGroupUser
        self.isGroupAll = isGroupAll
        self.payload = payload
    }
}

public struct TydomGroup: Sendable, Equatable {
    public struct DeviceMember: Sendable, Equatable {
        public struct EndpointMember: Sendable, Equatable {
            public let id: Int

            public init(id: Int) {
                self.id = id
            }
        }

        public let id: Int
        public let endpoints: [EndpointMember]

        public init(id: Int, endpoints: [EndpointMember]) {
            self.id = id
            self.endpoints = endpoints
        }
    }

    public struct AreaMember: Sendable, Equatable {
        public let id: Int

        public init(id: Int) {
            self.id = id
        }
    }

    public let id: Int
    public let devices: [DeviceMember]
    public let areas: [AreaMember]
    public let payload: [String: JSONValue]

    public init(
        id: Int,
        devices: [DeviceMember],
        areas: [AreaMember],
        payload: [String: JSONValue]
    ) {
        self.id = id
        self.devices = devices
        self.areas = areas
        self.payload = payload
    }
}

public struct TydomMoment: Sendable, Equatable {
    public let payload: [String: JSONValue]

    public init(payload: [String: JSONValue]) {
        self.payload = payload
    }
}

public struct TydomArea: Sendable, Equatable {
    public let id: Int?
    public let payload: [String: JSONValue]

    public init(id: Int?, payload: [String: JSONValue]) {
        self.id = id
        self.payload = payload
    }
}

public struct TydomMetadataEntry: Sendable, Equatable {
    public let id: Int?
    public let payload: [String: JSONValue]

    public init(id: Int?, payload: [String: JSONValue]) {
        self.id = id
        self.payload = payload
    }
}

struct TydomDeviceInfo: Sendable, Equatable {
    let name: String
    let usage: String
    let metadata: [String: JSONValue]?

    init(name: String, usage: String, metadata: [String: JSONValue]? = nil) {
        self.name = name
        self.usage = usage
        self.metadata = metadata
    }
}

public struct TydomDeviceDataEntry: Sendable, Equatable {
    public let name: String
    public let validity: String?
    public let value: JSONValue
    public let payload: [String: JSONValue]

    public init(
        name: String,
        validity: String?,
        value: JSONValue,
        payload: [String: JSONValue]
    ) {
        self.name = name
        self.validity = validity
        self.value = value
        self.payload = payload
    }
}


public struct TydomDevice: Sendable, Equatable {
    public let id: Int
    public let endpointId: Int
    public let uniqueId: String
    public let name: String
    public let usage: String
    public let kind: TydomDeviceKind
    public let data: [String: JSONValue]
    public let entries: [TydomDeviceDataEntry]
    public let metadata: [String: JSONValue]?

    public init(
        id: Int,
        endpointId: Int,
        uniqueId: String,
        name: String,
        usage: String,
        kind: TydomDeviceKind,
        data: [String: JSONValue],
        entries: [TydomDeviceDataEntry],
        metadata: [String: JSONValue]?
    ) {
        self.id = id
        self.endpointId = endpointId
        self.uniqueId = uniqueId
        self.name = name
        self.usage = usage
        self.kind = kind
        self.data = data
        self.entries = entries
        self.metadata = metadata
    }
}

public enum TydomDeviceKind: Sendable, Equatable {
    case shutter
    case window
    case door
    case garage
    case gate
    case light
    case energy
    case smoke
    case boiler
    case alarm
    case weather
    case water
    case thermo
    case other(String)

    public static func fromUsage(_ usage: String) -> TydomDeviceKind {
        switch usage {
        case "shutter", "klineShutter", "awning", "swingShutter":
            return .shutter
        case "window", "windowFrench", "windowSliding", "klineWindowFrench", "klineWindowSliding":
            return .window
        case "belmDoor", "klineDoor":
            return .door
        case "garage_door":
            return .garage
        case "gate":
            return .gate
        case "light":
            return .light
        case "conso":
            return .energy
        case "sensorDFR":
            return .smoke
        case "boiler", "sh_hvac", "electric", "aeraulic", "re2020ControlBoiler":
            return .boiler
        case "alarm":
            return .alarm
        case "weather":
            return .weather
        case "sensorDF":
            return .water
        case "sensorThermo":
            return .thermo
        default:
            return .other(usage)
        }
    }
}
