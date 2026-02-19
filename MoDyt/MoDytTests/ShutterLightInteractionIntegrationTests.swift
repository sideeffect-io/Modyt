import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct NewShutterRepositoryTests {
    @Test
    func observeShutterTargets_initializesMissingRowsFromDevicePositions() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )

        await deviceRepository.upsertDevices([
            makeTydomShutter(uniqueId: "1001_1", id: 1, endpointId: 1001, level: 24),
            makeTydomShutter(uniqueId: "1002_1", id: 1, endpointId: 1002, level: 88)
        ])

        let stream = await repository.observeShutterTargets(
            uniqueIds: ["1001_1", "1002_1", "1003_1"]
        )
        var iterator = stream.makeAsyncIterator()
        let snapshot = await iterator.next()

        #expect(snapshot == [24, 88, 0])
    }

    @Test
    func setShutterTarget_createsAndUpdatesTargetRow() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )
        let uniqueId = "2001_2"

        await repository.setShutterTarget(uniqueId: uniqueId, targetPosition: 110)

        let stream = await repository.observeShutterTargets(uniqueIds: [uniqueId])
        var iterator = stream.makeAsyncIterator()

        let createdSnapshot = await iterator.next()
        #expect(createdSnapshot == [100])

        await repository.setShutterTarget(uniqueId: uniqueId, targetPosition: 44)
        let updatedSnapshot = await iterator.next()
        #expect(updatedSnapshot == [44])
    }

    @Test
    func observeShuttersPositions_combinesActualAndTargetAveragesIntoSteps() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )

        await deviceRepository.upsertDevices([
            makeTydomShutter(uniqueId: "3001_3", id: 3, endpointId: 3001, level: 0),
            makeTydomShutter(uniqueId: "3002_3", id: 3, endpointId: 3002, level: 100)
        ])

        let stream = await repository.observeShuttersPositions(uniqueIds: ["3001_3", "3002_3"])
        let recorder = TestRecorder<(ShutterStep, ShutterStep)>()

        let observationTask = Task {
            for await snapshot in stream {
                await recorder.record((snapshot.actual, snapshot.target))
            }
        }
        defer { observationTask.cancel() }

        let receivedInitial = await waitUntil {
            await recorder.values.contains(where: { $0 == (.half, .half) })
        }
        #expect(receivedInitial)

        await repository.setShutterTarget(uniqueId: "3001_3", targetPosition: 90)
        let receivedUpdatedTarget = await waitUntil {
            await recorder.values.contains(where: { $0 == (.half, .open) })
        }
        #expect(receivedUpdatedTarget)
    }

    @Test
    func setShuttersTarget_setsTargetForAllProvidedIds() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )

        let uniqueIds = ["4001_4", "4002_4", "4003_4"]
        await repository.setShuttersTarget(uniqueIds: uniqueIds, step: .threeQuarter)

        let stream = await repository.observeShutterTargets(uniqueIds: uniqueIds)
        var iterator = stream.makeAsyncIterator()
        let snapshot = await iterator.next()

        #expect(snapshot == [75, 75, 75])
    }

    @Test
    func observeShuttersPositions_normalizesActualUsingDescriptorRange() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let repository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            log: { _ in }
        )

        await deviceRepository.upsertDevices([
            TydomDevice(
                id: 1,
                endpointId: 5001,
                uniqueId: "5001_1",
                name: "Shutter 5001_1",
                usage: "shutter",
                kind: .shutter,
                data: ["position": .number(1)],
                metadata: [
                    "position": .object([
                        "min": .number(0),
                        "max": .number(1)
                    ])
                ]
            )
        ])

        let stream = await repository.observeShuttersPositions(uniqueIds: ["5001_1"])
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()

        #expect(first?.actual == .open)
        #expect(first?.target == .open)
    }

    @Test
    func stalePersistedTarget_isResetToCurrentPositionOnObservation() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let clock = MutableNow()
        let repository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            now: clock.now,
            log: { _ in }
        )

        await deviceRepository.upsertDevices([
            makeTydomShutter(uniqueId: "6001_6", id: 6, endpointId: 6001, level: 0)
        ])

        await repository.setShutterTarget(uniqueId: "6001_6", targetPosition: 100)
        clock.advance(by: 120)

        let stream = await repository.observeShuttersPositions(uniqueIds: ["6001_6"])
        var iterator = stream.makeAsyncIterator()
        let first = await iterator.next()

        #expect(first?.actual == .closed)
        #expect(first?.target == .closed)
    }

    private func makeTydomShutter(
        uniqueId: String,
        id: Int,
        endpointId: Int,
        level: Double
    ) -> TydomDevice {
        TydomDevice(
            id: id,
            endpointId: endpointId,
            uniqueId: uniqueId,
            name: "Shutter \(uniqueId)",
            usage: "shutter",
            kind: .shutter,
            data: ["level": .number(level)],
            metadata: [
                "level": .object([
                    "min": .number(0),
                    "max": .number(100)
                ])
            ]
        )
    }
}

private final class MutableNow: @unchecked Sendable {
    private let lock = NSLock()
    private var current: Date = Date(timeIntervalSince1970: 1_700_000_000)

    var now: @Sendable () -> Date {
        { [weak self] in
            self?.value ?? Date(timeIntervalSince1970: 1_700_000_000)
        }
    }

    func advance(by seconds: TimeInterval) {
        lock.lock()
        current = current.addingTimeInterval(seconds)
        lock.unlock()
    }

    private var value: Date {
        lock.lock()
        defer { lock.unlock() }
        return current
    }
}
