import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct DeviceRepositoryCommandEchoTests {
    @Test
    func applyMessage_ignoresEchoMessage() async {
        let repository = DeviceRepository(
            databasePath: TestSupport.temporaryDatabasePath(),
            now: { Date(timeIntervalSince1970: 1_000) },
            log: { _ in }
        )

        await repository.applyMessage(
            .echo(TydomEchoMessage(
                uriOrigin: "/devices/1/endpoints/2/data",
                transactionId: "echo-1",
                statusCode: 200,
                reason: "OK",
                headers: [:]
            ))
        )

        let snapshot = (try? await repository.listDevices()) ?? []
        #expect(snapshot.isEmpty)
    }

    @Test
    func applyMessage_appliesDevicesMessage() async throws {
        let repository = DeviceRepository(
            databasePath: TestSupport.temporaryDatabasePath(),
            now: { Date(timeIntervalSince1970: 1_000) },
            log: { _ in }
        )

        await repository.applyMessage(
            .devices([makeShutter(level: 25)], transactionId: "telemetry-1")
        )

        let snapshot = try await repository.listDevices()
        #expect(snapshot.count == 1)
        let first = try #require(snapshot.first)
        #expect(first.uniqueId == "2_1")
        #expect(first.data["level"] == .number(25))
    }

    @Test
    func applyMessage_appliesDevicesMessageForCommandLikeTransactionId() async throws {
        let repository = DeviceRepository(
            databasePath: TestSupport.temporaryDatabasePath(),
            now: { Date(timeIntervalSince1970: 1_000) },
            log: { _ in }
        )

        await repository.applyMessage(
            .devices(
                [makeShutter(data: ["level": .number(75)])],
                transactionId: "command-tx"
            )
        )

        let snapshot = try await repository.listDevices()
        #expect(snapshot.count == 1)
        let first = try #require(snapshot.first)
        #expect(first.data["level"] == .number(75))
    }

    private func makeShutter(level: Double) -> TydomDevice {
        makeShutter(data: ["level": .number(level)])
    }

    private func makeShutter(data: [String: JSONValue]) -> TydomDevice {
        TydomDevice(
            id: 1,
            endpointId: 2,
            uniqueId: "2_1",
            name: "Living Room",
            usage: "shutter",
            kind: .shutter,
            data: data,
            metadata: nil
        )
    }
}
