import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct DeviceDatasourceTests {
    @Test
    func observeDevicesDoesNotEmitWhenDatabaseIsEmpty() async throws {
        let databasePath = temporarySQLitePath()
        defer {
            try? FileManager.default.removeItem(atPath: databasePath)
        }

        let datasource = DeviceDatasource(databasePath: databasePath)
        try await datasource.startIfNeeded()

        let stream = await datasource.observeDevices()
        let first = await firstValue(
            from: stream,
            timeoutNanoseconds: 150_000_000
        )

        #expect(first == nil)
    }

    @Test
    func observeDevicesFirstSnapshotUsesPersistedRecords() async throws {
        let databasePath = temporarySQLitePath()
        defer {
            try? FileManager.default.removeItem(atPath: databasePath)
        }

        let datasource = DeviceDatasource(databasePath: databasePath)
        try await datasource.startIfNeeded()

        await datasource.upsertDevices(
            [makeShutter(deviceId: 10, endpointId: 1, position: 100)],
            source: "test"
        )

        let stream = await datasource.observeDevices()
        let first = await firstValue(from: stream)

        #expect(first?.count == 1)
        #expect(first?.first?.uniqueId == "10:1")
        #expect(first?.first?.data["position"] == .number(100))
    }

    private func makeShutter(deviceId: Int, endpointId: Int, position: Int) -> TydomDevice {
        TydomDevice(
            deviceId: deviceId,
            endpointId: endpointId,
            name: "Cuisine",
            usage: "shutter",
            kind: .shutter,
            data: [
                "position": .number(Double(position)),
            ],
            entries: [],
            metadata: [
                "position": .object([
                    "min": .number(0),
                    "max": .number(100),
                ]),
            ]
        )
    }

    private func temporarySQLitePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("device-datasource-tests", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
            .appendingPathComponent("\(UUID().uuidString).sqlite")
            .path
    }

    private func firstValue<S: AsyncSequence & Sendable>(
        from stream: S,
        timeoutNanoseconds: UInt64 = 1_000_000_000
    ) async -> S.Element? where S.Element: Sendable {
        await withTaskGroup(of: S.Element?.self) { group in
            group.addTask {
                var iterator = stream.makeAsyncIterator()
                do {
                    return try await iterator.next()
                } catch {
                    return nil
                }
            }

            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
                return nil
            }

            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }
}
