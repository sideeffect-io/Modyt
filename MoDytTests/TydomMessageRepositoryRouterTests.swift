import Foundation
import DeltaDoreClient
import Testing
@testable import MoDyt

struct TydomMessageRepositoryRouterTests {
    @Test
    func startIfNeededAndIngestPersistsSupportedMessages() async throws {
        let fixture = RouterFixture()
        defer { fixture.cleanup() }

        try await fixture.router.startIfNeeded()

        await fixture.router.ingest(.devices(
            [
                TydomDevice(
                    deviceId: 10,
                    endpointId: 1,
                    name: "Desk Lamp",
                    usage: "light",
                    kind: .light,
                    data: [
                        "level": .number(70),
                        "powered": .bool(true),
                    ],
                    entries: [],
                    metadata: [
                        "level": .object([
                            "unit": .string("%")
                        ])
                    ]
                )
            ],
            metadata: makeTestMetadata(transactionId: "tx-devices", uriOrigin: "/devices/data")
        ))
        await fixture.router.ingest(.groupMetadata(
            [
                TydomGroupMetadata(
                    id: 7,
                    name: "All Lights",
                    usage: "light",
                    picto: "bulb",
                    isGroupUser: true,
                    isGroupAll: false,
                    payload: [:]
                )
            ],
            metadata: makeTestMetadata(transactionId: "tx-group-meta", uriOrigin: "/configs/file")
        ))
        await fixture.router.ingest(.groups(
            [
                TydomGroup(
                    id: 7,
                    devices: [
                        .init(
                            id: 10,
                            endpoints: [.init(id: 1)]
                        )
                    ],
                    areas: [],
                    payload: [:]
                )
            ],
            metadata: makeTestMetadata(transactionId: "tx-groups", uriOrigin: "/groups/file")
        ))
        await fixture.router.ingest(.scenarios(
            [
                TydomScenario(
                    id: 9,
                    name: "Good Night",
                    type: "user",
                    picto: "moon.stars",
                    ruleId: "rule-9",
                    payload: [
                        "active": .bool(true)
                    ]
                )
            ],
            metadata: makeTestMetadata(transactionId: "tx-scenes", uriOrigin: "/scenarios/file")
        ))

        let devices = try await fixture.deviceRepository.listAll()
        let groups = try await fixture.groupRepository.listAll()
        let scenes = try await fixture.sceneRepository.listAll()

        #expect(devices.count == 1)
        #expect(devices[0].id == .init(deviceId: 10, endpointId: 1))
        #expect(devices[0].data["level"] == .number(70))
        #expect(devices[0].metadata?["level"] == .object(["unit": .string("%")]))

        #expect(groups.count == 1)
        #expect(groups[0].name == "All Lights")
        #expect(groups[0].memberIdentifiers == [.init(deviceId: 10, endpointId: 1)])

        #expect(scenes.count == 1)
        #expect(scenes[0].id == "9")
        #expect(scenes[0].name == "Good Night")
        #expect(scenes[0].payload == ["active": .bool(true)])
    }

    @Test
    func ackMessagesAreForwardedAndIgnoredMessagesDoNotMutateRepositories() async throws {
        let fixture = RouterFixture()
        defer { fixture.cleanup() }

        try await fixture.router.startIfNeeded()

        await fixture.router.ingest(.ack(
            makeTestACK(statusCode: 202),
            metadata: makeTestMetadata(transactionId: "tx-ack", uriOrigin: "/devices/data")
        ))
        await fixture.router.ingest(.raw(
            makeTestMetadata(transactionId: "tx-raw", uriOrigin: "/ignored")
        ))

        let ack = try await fixture.ackRepository.waitForACKMessage(transactionId: "tx-ack")

        #expect(ack.ack.statusCode == 202)
        #expect((try await fixture.deviceRepository.listAll()).isEmpty)
        #expect((try await fixture.groupRepository.listAll()).isEmpty)
        #expect((try await fixture.sceneRepository.listAll()).isEmpty)
    }
}

private struct RouterFixture {
    let databasePath = testTemporarySQLitePath("tydom-router-tests")
    let deviceRepository: DeviceRepository
    let groupRepository: GroupRepository
    let sceneRepository: SceneRepository
    let ackRepository: ACKRepository
    let router: TydomMessageRepositoryRouter

    init() {
        let deviceRepository = DeviceRepository.makeDeviceRepository(databasePath: databasePath)
        let groupRepository = GroupRepository.makeGroupRepository(databasePath: databasePath)
        let sceneRepository = SceneRepository.makeSceneRepository(databasePath: databasePath)
        let ackRepository = ACKRepository()

        self.deviceRepository = deviceRepository
        self.groupRepository = groupRepository
        self.sceneRepository = sceneRepository
        self.ackRepository = ackRepository
        self.router = TydomMessageRepositoryRouter(
            deviceRepository: deviceRepository,
            groupRepository: groupRepository,
            sceneRepository: sceneRepository,
            ackRepository: ackRepository
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(atPath: databasePath)
    }
}
