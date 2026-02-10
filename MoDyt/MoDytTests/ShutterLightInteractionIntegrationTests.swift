import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct ShutterLightInteractionIntegrationTests {
    @Test
    func unchangedShutterTimestampDoesNotCommitPendingTarget() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let shutterRepository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            autoObserveDevices: false,
            log: { _ in }
        )

        let shutterUniqueId = "1_100"
        let lightUniqueId = "1_200"
        let t0 = Date(timeIntervalSince1970: 1000)
        let t1 = Date(timeIntervalSince1970: 1001)
        let t2 = Date(timeIntervalSince1970: 1002)
        let t3 = Date(timeIntervalSince1970: 1003)

        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 100, updatedAt: t0),
            makeLightDevice(uniqueId: lightUniqueId, isOn: false)
        ])

        await shutterRepository.setTarget(uniqueId: shutterUniqueId, targetStep: .half, originStep: .open)
        var snapshot = await currentSnapshot(for: shutterUniqueId, in: shutterRepository)
        #expect(snapshot?.actualStep == .open)
        #expect(snapshot?.targetStep == .half)

        // First target echo keeps optimistic target pending.
        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 50, updatedAt: t1),
            makeLightDevice(uniqueId: lightUniqueId, isOn: false)
        ])
        snapshot = await currentSnapshot(for: shutterUniqueId, in: shutterRepository)
        #expect(snapshot?.actualStep == .open)
        #expect(snapshot?.targetStep == .half)

        // Light-only change with unchanged shutter timestamp must not commit the pending target.
        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 50, updatedAt: t1),
            makeLightDevice(uniqueId: lightUniqueId, isOn: true)
        ])
        snapshot = await currentSnapshot(for: shutterUniqueId, in: shutterRepository)
        #expect(snapshot?.actualStep == .open, "after light update snapshot=\(String(describing: snapshot))")
        #expect(snapshot?.targetStep == .half, "after light update snapshot=\(String(describing: snapshot))")

        // Stale origin payload while pending keeps the pending state.
        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 100, updatedAt: t2),
            makeLightDevice(uniqueId: lightUniqueId, isOn: false)
        ])
        snapshot = await currentSnapshot(for: shutterUniqueId, in: shutterRepository)
        #expect(snapshot?.actualStep == .open, "after stale origin snapshot=\(String(describing: snapshot))")
        #expect(snapshot?.targetStep == .half, "after stale origin snapshot=\(String(describing: snapshot))")

        // Later target payload with a new shutter timestamp commits.
        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 50, updatedAt: t3),
            makeLightDevice(uniqueId: lightUniqueId, isOn: false)
        ])
        snapshot = await currentSnapshot(for: shutterUniqueId, in: shutterRepository)
        #expect(snapshot?.actualStep == .half, "final snapshot=\(String(describing: snapshot))")
        #expect(snapshot?.targetStep == nil, "final snapshot=\(String(describing: snapshot))")
    }

    @Test
    func unchangedShutterControlWithNewTimestampDoesNotCommitPendingTarget() async {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let shutterRepository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: deviceRepository,
            autoObserveDevices: false,
            log: { _ in }
        )

        let shutterUniqueId = "1_300"
        let lightUniqueId = "1_400"
        let t0 = Date(timeIntervalSince1970: 2000)
        let t1 = Date(timeIntervalSince1970: 2001)
        let t2 = Date(timeIntervalSince1970: 2002)
        let t3 = Date(timeIntervalSince1970: 2003)

        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 100, updatedAt: t0),
            makeLightDevice(uniqueId: lightUniqueId, isOn: false)
        ])

        await shutterRepository.setTarget(uniqueId: shutterUniqueId, targetStep: .half, originStep: .open)

        // First target echo keeps optimistic target pending.
        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 50, updatedAt: t1),
            makeLightDevice(uniqueId: lightUniqueId, isOn: false)
        ])

        // Same shutter control value with a new timestamp must not commit.
        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 50, updatedAt: t2),
            makeLightDevice(uniqueId: lightUniqueId, isOn: true)
        ])

        var snapshot = await currentSnapshot(for: shutterUniqueId, in: shutterRepository)
        #expect(snapshot?.actualStep == .open, "after unchanged control snapshot=\(String(describing: snapshot))")
        #expect(snapshot?.targetStep == .half, "after unchanged control snapshot=\(String(describing: snapshot))")

        // A true shutter movement to origin should still be reflected while pending.
        await shutterRepository.syncDevices([
            makeShutterDevice(uniqueId: shutterUniqueId, level: 100, updatedAt: t3),
            makeLightDevice(uniqueId: lightUniqueId, isOn: true)
        ])

        snapshot = await currentSnapshot(for: shutterUniqueId, in: shutterRepository)
        #expect(snapshot?.actualStep == .open, "after true movement snapshot=\(String(describing: snapshot))")
        #expect(snapshot?.targetStep == .half, "after true movement snapshot=\(String(describing: snapshot))")
    }

    private func currentSnapshot(
        for uniqueId: String,
        in repository: ShutterRepository
    ) async -> ShutterSnapshot? {
        let stream = await repository.observeShutter(uniqueId: uniqueId)
        var iterator = stream.makeAsyncIterator()
        return await iterator.next() ?? nil
    }

    private func makeShutterDevice(
        uniqueId: String,
        level: Double,
        updatedAt: Date
    ) -> DeviceRecord {
        var device = TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Main Shutter",
            usage: "shutter",
            data: ["level": .number(level)],
            metadata: ["level": .object(["min": .number(0), "max": .number(100)])]
        )
        device.updatedAt = updatedAt
        return device
    }

    private func makeLightDevice(uniqueId: String, isOn: Bool) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: uniqueId,
            name: "Driveway Light",
            usage: "light",
            data: ["on": .bool(isOn)]
        )
    }
}
