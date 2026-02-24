import Foundation

struct TydomDecodedEnvelope: Sendable, Equatable {
    let metadata: TydomMessageMetadata
    let payload: TydomDecodedPayload
    let cacheMutations: [TydomCacheMutation]
    let effects: [TydomMessageEffect]

    init(
        raw: TydomRawMessage,
        payload: TydomDecodedPayload,
        cacheMutations: [TydomCacheMutation] = [],
        effects: [TydomMessageEffect] = []
    ) {
        self.init(
            metadata: TydomMessageMetadata(raw: raw),
            payload: payload,
            cacheMutations: cacheMutations,
            effects: effects
        )
    }

    init(
        metadata: TydomMessageMetadata,
        payload: TydomDecodedPayload,
        cacheMutations: [TydomCacheMutation] = [],
        effects: [TydomMessageEffect] = []
    ) {
        self.metadata = metadata
        self.payload = payload
        self.cacheMutations = cacheMutations
        self.effects = effects
    }

    var raw: TydomRawMessage {
        metadata.raw
    }
}

enum TydomDecodedPayload: Sendable, Equatable {
    case gatewayInfo(TydomGatewayInfo)
    case deviceUpdates([TydomDeviceUpdate])
    case devicesMeta([TydomMetadataEntry])
    case devicesCMeta([TydomMetadataEntry])
    case scenarios([TydomScenarioPayload])
    case groupMetadata([TydomGroupMetadata])
    case groups([TydomGroup])
    case moments([TydomMoment])
    case areas([TydomArea])
    case areasMeta([TydomMetadataEntry])
    case areasCMeta([TydomMetadataEntry])
    case ack(TydomAck)
    case none
}

enum TydomCacheMutation: Sendable, Equatable {
    case deviceEntry(TydomDeviceCacheEntry)
    case scenarioMetadata(TydomScenarioMetadata)
}

struct TydomScenarioMetadata: Sendable, Equatable {
    let id: Int
    let name: String
    let type: String
    let picto: String
    let ruleId: String?

    init(
        id: Int,
        name: String,
        type: String,
        picto: String,
        ruleId: String?
    ) {
        self.id = id
        self.name = name
        self.type = type
        self.picto = picto
        self.ruleId = ruleId
    }
}

struct TydomScenarioPayload: Sendable, Equatable {
    let id: Int
    let payload: [String: PayloadValue]

    init(id: Int, payload: [String: PayloadValue]) {
        self.id = id
        self.payload = payload
    }
}

struct TydomDeviceUpdate: Sendable, Equatable {
    enum Source: Sendable, Equatable {
        case data
        case cdata
    }

    let id: Int
    let endpointId: Int
    let uniqueId: String
    let data: [String: PayloadValue]
    let entries: [TydomDeviceDataEntry]
    let metadata: [String: PayloadValue]?
    let cdataEntries: [PayloadValue]?
    let source: Source

    init(
        id: Int,
        endpointId: Int,
        uniqueId: String,
        data: [String: PayloadValue],
        entries: [TydomDeviceDataEntry] = [],
        metadata: [String: PayloadValue]? = nil,
        cdataEntries: [PayloadValue]? = nil,
        source: Source
    ) {
        self.id = id
        self.endpointId = endpointId
        self.uniqueId = uniqueId
        self.data = data
        self.entries = entries
        self.metadata = metadata
        self.cdataEntries = cdataEntries
        self.source = source
    }
}
