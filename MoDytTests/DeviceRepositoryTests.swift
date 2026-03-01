import Foundation
import Testing
@testable import MoDyt

struct DeviceRepositoryTests {
    @Test
    func firstUpsertKeepsIncomingShutterValuesOnFreshDatabase() async throws {
        let databasePath = temporarySQLitePath()
        defer {
            try? FileManager.default.removeItem(atPath: databasePath)
        }

        let repository = DeviceRepository.makeDeviceRepository(databasePath: databasePath)
        try await repository.startIfNeeded()

        let upsert = DeviceUpsert(
            id: .init(deviceId: 10, endpointId: 1),
            name: "Cuisine",
            usage: "shutter",
            kind: "roller",
            data: [
                "position": .number(100),
                "level": .number(100),
            ],
            metadata: [
                "position": .object([
                    "min": .number(0),
                    "max": .number(100),
                ]),
            ]
        )

        try await repository.upsert([upsert])

        let stored = try await repository.get(upsert.id)
        #expect(stored != nil)
        #expect(stored?.data == upsert.data)
        #expect(stored?.metadata == upsert.metadata)
        #expect(stored?.shutterPosition == 100)
    }

    @Test
    func upsertMergesWithExistingDeviceWithoutTransformingPosition() async throws {
        let databasePath = temporarySQLitePath()
        defer {
            try? FileManager.default.removeItem(atPath: databasePath)
        }

        let repository = DeviceRepository.makeDeviceRepository(databasePath: databasePath)
        try await repository.startIfNeeded()

        try await repository.upsert([
            DeviceUpsert(
                id: .init(deviceId: 10, endpointId: 1),
                name: "Cuisine",
                usage: "shutter",
                kind: "roller",
                data: [
                    "position": .number(100),
                    "level": .number(100),
                ],
                metadata: [
                    "position": .object([
                        "min": .number(0),
                        "max": .number(100),
                    ]),
                ]
            ),
        ])

        try await repository.upsert([
            DeviceUpsert(
                id: .init(deviceId: 10, endpointId: 1),
                name: "Cuisine",
                usage: "shutter",
                kind: "roller",
                data: [
                    "position": .number(75),
                    "target": .number(75),
                ],
                metadata: nil
            ),
        ])

        let all = try await repository.listAll()
        #expect(all.count == 1)

        let stored = try await repository.get(.init(deviceId: 10, endpointId: 1))
        #expect(stored != nil)
        #expect(stored?.data["position"] == .number(75))
        #expect(stored?.data["target"] == .number(75))
        #expect(stored?.metadata?["position"] == .object([
            "min": .number(0),
            "max": .number(100),
        ]))
        #expect(stored?.shutterPosition == 75)
    }

    @Test
    func observeByIDsDoesNotEmitWhenDatabaseIsEmpty() async throws {
        let databasePath = temporarySQLitePath()
        defer {
            try? FileManager.default.removeItem(atPath: databasePath)
        }

        let repository = DeviceRepository.makeDeviceRepository(databasePath: databasePath)
        try await repository.startIfNeeded()

        let stream = await repository.observeByIDs([.init(deviceId: 10, endpointId: 1)])
        let first = await firstValue(
            from: stream,
            timeoutNanoseconds: 150_000_000
        )

        #expect(first == nil)
    }

    @Test
    func observeByIDsFirstSnapshotUsesPersistedValues() async throws {
        let databasePath = temporarySQLitePath()
        defer {
            try? FileManager.default.removeItem(atPath: databasePath)
        }

        let repository = DeviceRepository.makeDeviceRepository(databasePath: databasePath)
        try await repository.startIfNeeded()

        try await repository.upsert([
            DeviceUpsert(
                id: .init(deviceId: 10, endpointId: 1),
                name: "Cuisine",
                usage: "shutter",
                kind: "roller",
                data: ["position": .number(100)],
                metadata: nil
            ),
        ])

        let stream = await repository.observeByIDs([.init(deviceId: 10, endpointId: 1)])
        let first = await firstValue(from: stream)

        #expect(first?.count == 1)
        #expect(first?.first?.data["position"] == .number(100))
        #expect(first?.first?.shutterPosition == 100)
    }

    private func temporarySQLitePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("device-repository-tests", isDirectory: true)
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
