import Foundation
import Testing
@testable import DeltaDoreClient

@Test func tydomMessageDecoder_decodesGatewayInfo() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let json = "{\"version\":\"1.0\",\"mac\":\"AA:BB\"}"
    let payload = httpResponse(
        uriOrigin: "/info",
        transactionId: "123",
        body: json
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .gatewayInfo(let info, let transactionId) = message {
        #expect(transactionId == "123")
        #expect(info.payload["version"] == JSONValue.string("1.0"))
        #expect(info.payload["mac"] == JSONValue.string("AA:BB"))
    } else {
        #expect(Bool(false), "Expected gateway info")
    }
}

@Test func tydomMessageDecoder_decodesDevicesDataUsingCache() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "2_1" {
                return TydomDeviceInfo(name: "Living Room", usage: "shutter", metadata: nil)
            }
            return nil
        },
        applyCacheMutation: { _ in }
    )

    let json = """
    [
      {"id": 1, "endpoints": [
        {"id": 2, "error": 0, "data": [
          {"name": "level", "value": 50, "validity": "upToDate"}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(
        uriOrigin: "/devices/data",
        transactionId: "456",
        body: json
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .devices(let devices, let transactionId) = message {
        #expect(transactionId == "456")
        #expect(devices.count == 1)
        let device = devices[0]
        #expect(device.id == 1)
        #expect(device.endpointId == 2)
        #expect(device.uniqueId == "2_1")
        #expect(device.name == "Living Room")
        #expect(device.usage == "shutter")
        #expect(device.kind == TydomDeviceKind.shutter)
        #expect(device.data["level"] == JSONValue.number(50))
    } else {
        #expect(Bool(false), "Expected devices message")
    }
}

@Test func tydomMessageDecoder_decodesDeviceEndpointDataUsingUriOrigin() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "1757536112_1757536112" {
                return TydomDeviceInfo(name: "Shutter", usage: "shutter", metadata: nil)
            }
            return nil
        },
        applyCacheMutation: { _ in }
    )

    let json = """
    {"id":1757536112,"error":0,"data":[
      {"name":"position","value":50,"validity":"upToDate"},
      {"name":"jobsMP","value":3096,"validity":"upToDate"}
    ]}
    """
    let payload = httpResponse(
        uriOrigin: "/devices/1757536112/endpoints/1757536112/data",
        transactionId: "456-endpoint",
        body: json
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .devices(let devices, let transactionId) = message {
        #expect(transactionId == "456-endpoint")
        #expect(devices.count == 1)
        let device = devices[0]
        #expect(device.id == 1757536112)
        #expect(device.endpointId == 1757536112)
        #expect(device.uniqueId == "1757536112_1757536112")
        #expect(device.data["position"] == JSONValue.number(50))
        #expect(device.data["jobsMP"] == JSONValue.number(3096))
    } else {
        #expect(Bool(false), "Expected devices message")
    }
}

@Test func tydomMessageDecoder_filtersOnlyPolledUpdatesFromBroadcastDevicesData() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            switch uniqueId {
            case "1_1":
                return TydomDeviceInfo(name: "Light A", usage: "light", metadata: nil)
            case "2_2":
                return TydomDeviceInfo(name: "Light B", usage: "light", metadata: nil)
            default:
                return nil
            }
        },
        isPostPutPollingActive: { uniqueId in
            uniqueId == "2_2"
        },
        applyCacheMutation: { _ in }
    )

    let json = """
    [
      {"id": 1, "endpoints": [
        {"id": 1, "error": 0, "data": [
          {"name": "level", "value": 80, "validity": "upToDate"}
        ]}
      ]},
      {"id": 2, "endpoints": [
        {"id": 2, "error": 0, "data": [
          {"name": "level", "value": 40, "validity": "upToDate"}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(
        uriOrigin: "/devices/data",
        transactionId: "broadcast-1",
        body: json
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .devices(let devices, let transactionId) = message {
        #expect(transactionId == "broadcast-1")
        #expect(devices.count == 1)
        #expect(devices.first?.uniqueId == "1_1")
        #expect(devices.first?.data["level"] == JSONValue.number(80))
    } else {
        #expect(Bool(false), "Expected devices message")
    }
}

@Test func tydomMessageDecoder_keepsEndpointPollUpdateEvenWhenPollingIsActive() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "2_2" {
                return TydomDeviceInfo(name: "Light B", usage: "light", metadata: nil)
            }
            return nil
        },
        isPostPutPollingActive: { uniqueId in
            uniqueId == "2_2"
        },
        applyCacheMutation: { _ in }
    )

    let json = """
    {"id":2,"error":0,"data":[{"name":"level","value":40,"validity":"upToDate"}]}
    """
    let payload = httpResponse(
        uriOrigin: "/devices/2/endpoints/2/data",
        transactionId: "endpoint-1",
        body: json
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .devices(let devices, let transactionId) = message {
        #expect(transactionId == "endpoint-1")
        #expect(devices.count == 1)
        #expect(devices.first?.uniqueId == "2_2")
        #expect(devices.first?.data["level"] == JSONValue.number(40))
    } else {
        #expect(Bool(false), "Expected devices message")
    }
}

@Test func tydomDeviceKind_mapsRe2020ControlBoilerToBoiler() {
    // Given
    let usage = "re2020ControlBoiler"

    // When
    let kind = TydomDeviceKind.fromUsage(usage)

    // Then
    #expect(kind == .boiler)
}

@Test func tydomMessageDecoder_preservesLinkedAreaMetadataInDeviceData() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "2_1" {
                return TydomDeviceInfo(name: "Thermostat", usage: "re2020ControlBoiler", metadata: nil)
            }
            return nil
        },
        applyCacheMutation: { _ in }
    )

    let json = """
    [
      {"id": 1, "endpoints": [
        {"id": 2, "error": 0, "link": {"type":"area","subtype":"thermicCtrl","id":1739197415}, "data": [
          {"name": "ambientTemperature", "value": 23.7, "validity": "upToDate"}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(
        uriOrigin: "/devices/data",
        transactionId: "457",
        body: json
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .devices(let devices, let transactionId) = message {
        #expect(transactionId == "457")
        #expect(devices.count == 1)
        let device = devices[0]
        #expect(device.data["ambientTemperature"] == JSONValue.number(23.7))
        #expect(device.data["__linkedAreaId"] == JSONValue.number(1739197415))
        #expect(device.data["__linkedAreaSubtype"] == JSONValue.string("thermicCtrl"))
    } else {
        #expect(Bool(false), "Expected devices message")
    }
}

@Test func tydomMessageDecoder_decodesDevicesCDataForConsumption() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "1_10" {
                return TydomDeviceInfo(name: "Energy", usage: "conso", metadata: nil)
            }
            return nil
        },
        applyCacheMutation: { _ in }
    )

    let json = """
    [
      {"id": 10, "endpoints": [
        {"id": 1, "error": 0, "cdata": [
          {"name": "energyIndex", "parameters": {"dest": "ELEC"}, "values": {"counter": 123}}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(
        uriOrigin: "/devices/10/endpoints/1/cdata?name=energyIndex",
        transactionId: "789",
        body: json
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .devices(let devices, let transactionId) = message {
        #expect(transactionId == "789")
        #expect(devices.count == 1)
        let device = devices[0]
        #expect(device.name == "Energy")
        #expect(device.usage == "conso")
        #expect(device.kind == TydomDeviceKind.energy)
        #expect(device.data["energyIndex_ELEC"] == JSONValue.number(123))
    } else {
        #expect(Bool(false), "Expected devices message")
    }
}

@Test func tydomMessageDecoder_unsupportedMessageIsRaw() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let payload = httpResponse(
        uriOrigin: "/unknown",
        transactionId: "000",
        body: "{\"foo\":\"bar\"}"
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .raw(let raw) = message {
        #expect(raw.uriOrigin == "/unknown")
        #expect(raw.transactionId == "000")
    } else {
        #expect(Bool(false), "Expected raw message")
    }
}

@Test func tydomMessageDecoder_bodylessResponseDecodesEcho() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let payload = httpResponseWithoutBody(
        uriOrigin: "/devices/1/endpoints/2/data",
        transactionId: "echo-1"
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .echo(let echo) = message {
        #expect(echo.uriOrigin == "/devices/1/endpoints/2/data")
        #expect(echo.transactionId == "echo-1")
        #expect(echo.statusCode == 200)
        #expect(echo.reason == "OK")
    } else {
        #expect(Bool(false), "Expected echo message")
    }
}

@Test func tydomMessageDecoder_bodylessResponseMissingRoutingFieldsIsRaw() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let payload = Data(
        "HTTP/1.1 200 OK\r\nServer: gateway\r\nContent-Length: 0\r\n\r\n".utf8
    )

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .raw(let raw) = message {
        #expect(raw.transactionId == nil)
        #expect(raw.uriOrigin == nil)
    } else {
        #expect(Bool(false), "Expected raw message")
    }
}

@Test func tydomMessageDecoder_configsFileUpdatesCache() async {
    // Given
    let cache = TydomDeviceCacheStore()
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            await cache.deviceInfo(for: uniqueId)
        },
        applyCacheMutation: { mutation in
            switch mutation {
            case .deviceEntry(let entry):
                await cache.upsert(entry)
            case .scenarioMetadata:
                break
            }
        }
    )

    let body = """
    {"endpoints":[
      {"id_endpoint":2,"id_device":1,"name":"Living Room","last_usage":"shutter"},
      {"id_endpoint":3,"id_device":1,"name":"Alarm","last_usage":"alarm"}
    ]}
    """
    let payload = httpResponse(uriOrigin: "/configs/file", transactionId: "111", body: body)

    // When
    _ = await pipeline.decodeAndHydrate(payload)

    // Then
    let shutter = await cache.deviceInfo(for: "2_1")
    #expect(shutter?.name == "Living Room")
    #expect(shutter?.usage == "shutter")

    let alarm = await cache.deviceInfo(for: "3_1")
    #expect(alarm?.name == "Tyxal Alarm")
    #expect(alarm?.usage == "alarm")
}

@Test func tydomMessageDecoder_devicesMetaUpdatesCache() async {
    // Given
    let cache = TydomDeviceCacheStore()
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            await cache.deviceInfo(for: uniqueId)
        },
        applyCacheMutation: { mutation in
            switch mutation {
            case .deviceEntry(let entry):
                await cache.upsert(entry)
            case .scenarioMetadata:
                break
            }
        }
    )

    let body = """
    [
      {"id":1,"endpoints":[
        {"id":2,"metadata":[{"name":"position","min":0,"max":100}]}
      ]}
    ]
    """
    let payload = httpResponse(uriOrigin: "/devices/meta", transactionId: "222", body: body)

    // When
    _ = await pipeline.decodeAndHydrate(payload)

    await cache.upsert(TydomDeviceCacheEntry(uniqueId: "2_1", name: "Living Room", usage: "shutter"))
    let device = await cache.deviceInfo(for: "2_1")

    // Then
    #expect(device?.metadata?["position"] == JSONValue.object(["min": .number(0), "max": .number(100)]))
}

@Test func tydomMessageDecoder_devicesCmetaSchedulesPolling() async {
    // Given
    let body = """
    [
      {"id":1,"endpoints":[
        {"id":2,"cmetadata":[
          {"name":"energyIndex","parameters":[{"name":"dest","enum_values":["ELEC","GAS"]}]},
          {"name":"energyInstant","parameters":[{"name":"unit","enum_values":["ELEC_A"]}]}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(uriOrigin: "/devices/cmeta", transactionId: "333", body: body)
    let raw = TydomRawMessageParser.parse(payload)

    // When
    let envelope = TydomMessageDecoder.decode(raw)

    // Then
    #expect(envelope.effects.count == 1)
    if case .schedulePoll(let urls, let intervalSeconds) = envelope.effects[0] {
        #expect(intervalSeconds == 10)
        #expect(urls.contains("/devices/1/endpoints/2/cdata?name=energyIndex&dest=ELEC&reset=false"))
        #expect(urls.contains("/devices/1/endpoints/2/cdata?name=energyIndex&dest=GAS&reset=false"))
        #expect(urls.contains("/devices/1/endpoints/2/cdata?name=energyInstant&unit=ELEC_A&reset=false"))
    } else {
        #expect(Bool(false), "Expected schedulePoll effect")
    }
}

@Test func tydomMessageDecoder_devicesCmetaEnrichesCacheWithCapabilities() async {
    // Given
    let cache = TydomDeviceCacheStore()
    await cache.upsert(TydomDeviceCacheEntry(
        uniqueId: "2_1",
        name: "Living Room",
        usage: "shutter",
        metadata: [
            "position": .object(["min": .number(0), "max": .number(100)])
        ]
    ))
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            await cache.deviceInfo(for: uniqueId)
        },
        applyCacheMutation: { mutation in
            switch mutation {
            case .deviceEntry(let entry):
                await cache.upsert(entry)
            case .scenarioMetadata:
                break
            }
        }
    )

    let body = """
    [
      {"id":1,"endpoints":[
        {"id":2,"cmetadata":[
          {"name":"dataSupport","permission":"r","parameters":[
            {"name":"source","type":"string","enum_values":["DATA","INFO"]}
          ]},
          {"name":"histo","permission":"r","parameters":[
            {"name":"index","type":"numeric","min":-2147483648,"max":0},
            {"name":"nbElem","type":"numeric","min":0,"max":255}
          ]}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(uriOrigin: "/devices/cmeta", transactionId: "334", body: body)

    // When
    _ = await pipeline.decodeAndHydrate(payload)
    let metadata = await cache.deviceInfo(for: "2_1")?.metadata

    // Then
    #expect(metadata?["position"] == .object(["min": .number(0), "max": .number(100)]))
    let cmetadata = metadata?["__cmetadata"]?.arrayValue
    #expect(cmetadata?.count == 2)
    #expect(cmetadata?.first?.objectValue?["name"] == .string("dataSupport"))
    #expect(cmetadata?.first?.objectValue?["permission"] == .string("r"))
}

@Test func tydomMessageDecoder_eventsTriggerRefreshAll() async {
    // Given
    let payload = httpResponse(uriOrigin: "/events", transactionId: "444", body: "{}")
    let raw = TydomRawMessageParser.parse(payload)

    // When
    let envelope = TydomMessageDecoder.decode(raw)

    // Then
    #expect(envelope.effects == [.refreshAll])
}

@Test func tydomMessageDecoder_areasDataProducesAreasMessage() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let body = """
    [
      {"id": 101, "data": [{"name": "level", "value": 20, "validity": "upToDate"}]},
      {"id": 102, "data": []}
    ]
    """
    let payload = httpResponse(uriOrigin: "/areas/data", transactionId: "445", body: body)

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .areas(let areas, let transactionId) = message {
        #expect(transactionId == "445")
        #expect(areas.count == 2)
        #expect(areas[0].id == 101)
    } else {
        #expect(Bool(false), "Expected areas message")
    }
}

@Test func tydomMessageDecoder_scenariosMergeMetadata() async {
    // Given
    let scenarioStore = TydomScenarioMetadataStore()
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        scenarioMetadata: { id in
            await scenarioStore.metadata(for: id)
        },
        applyCacheMutation: { mutation in
            switch mutation {
            case .deviceEntry:
                break
            case .scenarioMetadata(let metadata):
                await scenarioStore.upsert(metadata)
            }
        }
    )

    let configsBody = """
    {"endpoints":[],
     "scenarios":[{"id":1,"name":"Wake","type":"NORMAL","picto":"SUN","rule_id":"r1"}]}
    """
    let configsPayload = httpResponse(uriOrigin: "/configs/file", transactionId: "555", body: configsBody)

    let scenariosBody = """
    {"scn":[{"id":1,"grpAct":[1]}]}
    """
    let scenariosPayload = httpResponse(uriOrigin: "/scenarios/file", transactionId: "556", body: scenariosBody)

    // When
    _ = await pipeline.decodeAndHydrate(configsPayload)
    let message = await pipeline.decodeAndHydrate(scenariosPayload)

    // Then
    if case .scenarios(let scenarios, let transactionId) = message {
        #expect(transactionId == "556")
        #expect(scenarios.count == 1)
        #expect(scenarios[0].name == "Wake")
        #expect(scenarios[0].type == "NORMAL")
        #expect(scenarios[0].picto == "SUN")
        #expect(scenarios[0].ruleId == "r1")
    } else {
        #expect(Bool(false), "Expected scenarios message")
    }
}

@Test func tydomMessageDecoder_configsFileProducesGroupMetadataMessage() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let configsBody = """
    {
      "endpoints": [],
      "groups": [
        {"id": 12932271, "name": "TOTAL", "usage": "light", "group_all": true, "is_group_user": false},
        {"id": 1722950600, "name": "Arriere TV", "usage": "light", "picto": "picto_lamp", "group_all": false, "is_group_user": true}
      ]
    }
    """
    let payload = httpResponse(uriOrigin: "/configs/file", transactionId: "557", body: configsBody)

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .groupMetadata(let metadata, let transactionId) = message {
        #expect(transactionId == "557")
        #expect(metadata.count == 2)
        #expect(metadata[0].id == 12932271)
        #expect(metadata[0].name == "TOTAL")
        #expect(metadata[0].usage == "light")
        #expect(metadata[0].isGroupAll == true)
        #expect(metadata[0].isGroupUser == false)
        #expect(metadata[1].id == 1722950600)
        #expect(metadata[1].picto == "picto_lamp")
        #expect(metadata[1].isGroupAll == false)
        #expect(metadata[1].isGroupUser == true)
    } else {
        #expect(Bool(false), "Expected group metadata message")
    }
}

@Test func tydomMessageDecoder_groupsFileDecodesTypedMembership() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { _ in nil },
        applyCacheMutation: { _ in }
    )

    let body = """
    {
      "payload": [
        {
          "payload": {
            "id": 12932271,
            "areas": [],
            "devices": [
              {"id": 1757536948, "endpoints": [{"id": 1757536948}]},
              {"id": 1757536792, "endpoints": [{"id": 1757536792}]}
            ]
          }
        },
        {
          "payload": {
            "id": 1375108641,
            "areas": [],
            "devices": []
          }
        }
      ]
    }
    """
    let payload = httpResponse(uriOrigin: "/groups/file", transactionId: "558", body: body)

    // When
    let message = await pipeline.decodeAndHydrate(payload)

    // Then
    if case .groups(let groups, let transactionId) = message {
        #expect(transactionId == "558")
        #expect(groups.count == 2)
        #expect(groups[0].id == 12932271)
        #expect(groups[0].devices.count == 2)
        #expect(groups[0].devices[0].id == 1757536948)
        #expect(groups[0].devices[0].endpoints.map(\.id) == [1757536948])
        #expect(groups[0].areas.isEmpty)
        #expect(groups[1].id == 1375108641)
        #expect(groups[1].devices.isEmpty)
    } else {
        #expect(Bool(false), "Expected groups message")
    }
}

@Test func tydomMessageDecoder_alarmCdataCreatesReplyChunkEffect() async {
    // Given
    let pipeline = MessagePipelineHarness(
        deviceInfo: { uniqueId in
            if uniqueId == "1_10" {
                return TydomDeviceInfo(name: "Alarm", usage: "alarm", metadata: nil)
            }
            return nil
        },
        applyCacheMutation: { _ in }
    )

    let body = """
    [
      {"id": 10, "endpoints": [
        {"id": 1, "error": 0, "cdata": [
          {"name": "alarm", "EOR": true, "value": "ON"}
        ]}
      ]}
    ]
    """
    let payload = httpResponse(
        uriOrigin: "/devices/10/endpoints/1/cdata?name=alarmCmd",
        transactionId: "999",
        body: body
    )

    // When
    let envelope = await pipeline.decodeAndHydrateEnvelope(payload)

    // Then
    #expect(envelope.effects.count == 1)
    if case .cdataReplyChunk(let chunk) = envelope.effects[0] {
        #expect(chunk.transactionId == "999")
        #expect(chunk.done == true)
        #expect(chunk.events.count == 1)
    } else {
        #expect(Bool(false), "Expected cdataReplyChunk effect")
    }
}

private struct MessagePipelineHarness: Sendable {
    let hydrator: TydomMessageHydrator

    init(
        deviceInfo: @escaping @Sendable (String) async -> TydomDeviceInfo?,
        scenarioMetadata: @escaping @Sendable (Int) async -> TydomScenarioMetadata? = { _ in nil },
        isPostPutPollingActive: @escaping @Sendable (String) async -> Bool = { _ in false },
        applyCacheMutation: @escaping @Sendable (TydomCacheMutation) async -> Void
    ) {
        self.hydrator = TydomMessageHydrator(
            dependencies: TydomMessageHydratorDependencies(
                deviceInfo: deviceInfo,
                scenarioMetadata: scenarioMetadata,
                applyCacheMutation: applyCacheMutation,
                isPostPutPollingActive: isPostPutPollingActive
            )
        )
    }

    func decodeAndHydrate(_ data: Data) async -> TydomMessage {
        let raw = TydomRawMessageParser.parse(data)
        let decoded = TydomMessageDecoder.decode(raw)
        let hydrated = await hydrator.hydrate(decoded)
        return hydrated.message
    }

    func decodeAndHydrateEnvelope(_ data: Data) async -> TydomHydratedEnvelope {
        let raw = TydomRawMessageParser.parse(data)
        let decoded = TydomMessageDecoder.decode(raw)
        return await hydrator.hydrate(decoded)
    }
}

private func httpResponse(uriOrigin: String, transactionId: String, body: String) -> Data {
    let bodyData = Data(body.utf8)
    let response = "HTTP/1.1 200 OK\r\n" +
        "Content-Length: \(bodyData.count)\r\n" +
        "Uri-Origin: \(uriOrigin)\r\n" +
        "Transac-Id: \(transactionId)\r\n" +
        "\r\n" +
        body
    return Data(response.utf8)
}

private func httpResponseWithoutBody(uriOrigin: String, transactionId: String) -> Data {
    let response = "HTTP/1.1 200 OK\r\n" +
        "Content-Length: 0\r\n" +
        "Uri-Origin: \(uriOrigin)\r\n" +
        "Transac-Id: \(transactionId)\r\n" +
        "\r\n"
    return Data(response.utf8)
}
