import Foundation
import Testing
@testable import DeltaDoreClient

@Test func frameFixture_inventoryMatchesExpectedMatrix() throws {
    let frames = try FrameCaptureFixture.loadRedacted()

    #expect(frames.count == 29)

    let counts = Dictionary(grouping: frames, by: \.uriOrigin).mapValues(\.count)
    #expect(counts["/info"] == 1)
    #expect(counts["/devices/data"] == 8)
    #expect(counts["/groups/file"] == 1)
    #expect(counts["/scenarios/file"] == 1)
    #expect(counts["/configs/file"] == 1)
    #expect(counts["/areas/data"] == 1)
    #expect(counts["/areas/meta"] == 1)
    #expect(counts["/areas/cmeta"] == 1)
    #expect(counts["/moments/file"] == 1)
    #expect(counts["/devices/meta"] == 1)
    #expect(counts["/devices/cmeta"] == 1)
    #expect(counts["/refresh/all"] == 1)

    let unsolicitedPutCount = frames.filter {
        $0.uriOrigin == "/devices/data" && $0.method == "PUT"
    }.count
    #expect(unsolicitedPutCount == 7)

    let responseFrames = frames.filter { $0.statusCode != nil }
    #expect(responseFrames.count == 22)
    #expect(responseFrames.allSatisfy { $0.statusCode == 200 })
}

@Test func frameFixture_replayParsesWithoutHTTPParserErrors() throws {
    let frames = try FrameCaptureFixture.loadRedacted()

    for frame in frames {
        let raw = TydomRawMessageParser.parse(frame.replayData)
        #expect(raw.parseError == nil)
        #expect(raw.uriOrigin == frame.uriOrigin)
        #expect(raw.transactionId == frame.transactionId)
    }
}

@Test func frameFixture_ackFramesAreTyped() async throws {
    let frames = try FrameCaptureFixture.loadRedacted()
    let ackFrames = frames.filter {
        $0.statusCode == 200
            && $0.method.hasPrefix("HTTP/")
            && $0.headers["content-length"] == "0"
            && (
                $0.uriOrigin == "/refresh/all"
                    || (($0.uriOrigin?.contains("/devices/") == true)
                        && ($0.uriOrigin?.hasSuffix("/data") == true))
            )
    }

    #expect(ackFrames.count == 3)

    let harness = LosslessPipelineHarness(deviceInfo: { _ in nil })
    for frame in ackFrames {
        let message = await harness.decodeAndHydrate(frame.replayData)
        if case .ack(let ack, let metadata) = message {
            #expect(ack.statusCode == 200)
            #expect(metadata.uriOrigin == frame.uriOrigin)
            #expect(metadata.transactionId == frame.transactionId)
            #expect(metadata.body == nil)
            #expect(metadata.bodyJSON == nil)
        } else {
            #expect(Bool(false), "Expected ack for frame \(frame.index)")
        }
    }
}

@Test func frameFixture_momentsFileSupportsMomKey() async throws {
    let frames = try FrameCaptureFixture.loadRedacted()
    let momentsFrame = try #require(frames.first { $0.uriOrigin == "/moments/file" })

    let harness = LosslessPipelineHarness()
    let message = await harness.decodeAndHydrate(momentsFrame.replayData)

    if case .moments(let moments, let metadata) = message {
        #expect(moments.count == 0)
        let bodyObject = metadata.bodyJSON?.objectValue
        #expect(bodyObject?["mom"] != nil)
        #expect(bodyObject?["moments"] == nil)
    } else {
        #expect(Bool(false), "Expected moments message")
    }
}

@Test func frameFixture_metadataFramesAreTyped() async throws {
    let frames = try FrameCaptureFixture.loadRedacted()
    let harness = LosslessPipelineHarness(deviceInfo: { _ in nil })

    let expectedByPath: [(path: String, matcher: (TydomMessage) -> Bool)] = [
        ("/devices/meta", { message in
            if case .devicesMeta = message { return true }
            return false
        }),
        ("/devices/cmeta", { message in
            if case .devicesCMeta = message { return true }
            return false
        }),
        ("/areas/meta", { message in
            if case .areasMeta = message { return true }
            return false
        }),
        ("/areas/cmeta", { message in
            if case .areasCMeta = message { return true }
            return false
        })
    ]

    for expected in expectedByPath {
        let frame = try #require(frames.first { $0.uriOrigin == expected.path })
        let message = await harness.decodeAndHydrate(frame.replayData)
        #expect(expected.matcher(message), "Expected typed message for \(expected.path)")
    }
}

@Test func frameFixture_deviceNullEntriesArePreserved() async throws {
    let frames = try FrameCaptureFixture.loadRedacted()
    let harness = LosslessPipelineHarness(deviceInfo: { uniqueId in
        TydomDeviceInfo(name: "Device \(uniqueId)", usage: "other", metadata: nil)
    })

    var sawThermicLevelNull = false
    var sawShutterCmdNull = false

    for frame in frames where frame.uriOrigin == "/devices/data" {
        let message = await harness.decodeAndHydrate(frame.replayData)
        guard case .devices(let devices, _) = message else { continue }

        for device in devices {
            for entry in device.entries {
                if entry.name == "thermicLevel", entry.value == .null {
                    sawThermicLevelNull = true
                    #expect(device.data["thermicLevel"] == .null)
                }
                if entry.name == "shutterCmd", entry.value == .null {
                    sawShutterCmdNull = true
                    #expect(device.data["shutterCmd"] == .null)
                }
            }
        }
    }

    #expect(sawThermicLevelNull)
    #expect(sawShutterCmdNull)
}

@Test func frameFixture_unsolicitedPutDevicesDataHasNilTransactionId() async throws {
    let frames = try FrameCaptureFixture.loadRedacted()
    let unsolicited = frames.filter {
        $0.uriOrigin == "/devices/data" && $0.method == "PUT"
    }
    #expect(unsolicited.count == 7)

    let harness = LosslessPipelineHarness(deviceInfo: { uniqueId in
        TydomDeviceInfo(name: "Device \(uniqueId)", usage: "other", metadata: nil)
    })

    for frame in unsolicited {
        let message = await harness.decodeAndHydrate(frame.replayData)
        if case .devices(_, let metadata) = message {
            #expect(metadata.transactionId == nil)
            #expect(metadata.uriOrigin == "/devices/data")
            if case .request = metadata.raw.frame {
                #expect(Bool(true))
            } else {
                #expect(Bool(false), "Expected request frame for unsolicited update")
            }
        } else {
            #expect(Bool(false), "Expected devices message for unsolicited PUT frame")
        }
    }
}

@Test func frameFixture_losslessMetadataBodyJSONInvariant() async throws {
    let frames = try FrameCaptureFixture.loadRedacted()
    let harness = LosslessPipelineHarness(deviceInfo: { uniqueId in
        TydomDeviceInfo(name: "Device \(uniqueId)", usage: "other", metadata: nil)
    })

    for frame in frames {
        guard let expectedJSON = frame.bodyJSON else { continue }
        let message = await harness.decodeAndHydrate(frame.replayData)
        #expect(message.metadata.uriOrigin == frame.uriOrigin)
        #expect(message.metadata.transactionId == frame.transactionId)
        #expect(message.metadata.bodyJSON == expectedJSON)
    }
}

@Test func frameFixture_configsPayloadRemainsRecoverable() async throws {
    let frames = try FrameCaptureFixture.loadRedacted()
    let frame = try #require(frames.first { $0.uriOrigin == "/configs/file" })

    let harness = LosslessPipelineHarness(deviceInfo: { _ in nil })
    let message = await harness.decodeAndHydrate(frame.replayData)

    if case .groupMetadata(_, let metadata) = message {
        let keys: Set<String> = metadata.bodyJSON?.objectValue.map { Set($0.keys) } ?? []
        #expect(keys.contains("version"))
        #expect(keys.contains("endpoints"))
        #expect(keys.contains("groups"))
        #expect(keys.contains("scenarios"))
        #expect(keys.contains("version_application"))
        #expect(keys.contains("areas"))
        #expect(keys.contains("zigbee_networks"))
    } else {
        #expect(Bool(false), "Expected groupMetadata message")
    }
}

private struct LosslessPipelineHarness: Sendable {
    let hydrator: TydomMessageHydrator

    init(
        deviceInfo: @escaping @Sendable (String) async -> TydomDeviceInfo? = { uniqueId in
            TydomDeviceInfo(name: "Device \(uniqueId)", usage: "other", metadata: nil)
        },
        scenarioMetadata: @escaping @Sendable (Int) async -> TydomScenarioMetadata? = { _ in nil },
        applyCacheMutation: @escaping @Sendable (TydomCacheMutation) async -> Void = { _ in }
    ) {
        self.hydrator = TydomMessageHydrator(
            dependencies: TydomMessageHydratorDependencies(
                deviceInfo: deviceInfo,
                scenarioMetadata: scenarioMetadata,
                applyCacheMutation: applyCacheMutation
            )
        )
    }

    func decodeAndHydrate(_ data: Data) async -> TydomMessage {
        let raw = TydomRawMessageParser.parse(data)
        let decoded = TydomMessageDecoder.decode(raw)
        let hydrated = await hydrator.hydrate(decoded)
        return hydrated.message
    }
}
