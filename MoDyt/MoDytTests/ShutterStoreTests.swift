import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
struct ShutterStoreTests {
    @Test
    func selectEmitsMappedNumericCommand() async {
        let device = makeShutterDevice(value: 0)
        let repository = makeRepository()
        await repository.syncDevices([device])

        var receivedKey: String?
        var receivedValue: JSONValue?

        let store = ShutterStore(
            device: device,
            shutterRepository: repository
        ) { key, value in
            receivedKey = key
            receivedValue = value
        }

        store.select(.half)

        #expect(receivedKey == "level")
        #expect(receivedValue?.numberValue == 50)
        #expect(store.effectiveTargetStep == .half)
        #expect(store.isInFlight)
    }

    @Test
    func repositoryStateSyncsAcrossStoreAndConvergesAfterEcho() async {
        let initial = makeShutterDevice(value: 0)
        let updated = makeShutterDevice(value: 50)
        let repository = makeRepository()

        await repository.syncDevices([initial])

        let store = ShutterStore(
            device: initial,
            shutterRepository: repository
        ) { _, _ in }

        await repository.setTarget(uniqueId: "shutter-1", targetStep: .half, originStep: .closed)
        await settleAsyncState()

        #expect(store.actualStep == .closed)
        #expect(store.effectiveTargetStep == .half)
        #expect(store.isInFlight)

        await repository.syncDevices([updated])
        await settleAsyncState()

        #expect(store.actualStep == .closed)
        #expect(store.effectiveTargetStep == .half)
        #expect(store.isInFlight)

        await repository.syncDevices([updated])
        await settleAsyncState()

        #expect(store.actualStep == .half)
        #expect(store.effectiveTargetStep == .half)
        #expect(!store.isInFlight)
    }

    @Test
    func repositorySyncUpdatesActualWhenNoTargetIsInFlight() async {
        let initial = makeShutterDevice(value: 0)
        let updated = makeShutterDevice(value: 75)
        let repository = makeRepository()

        await repository.syncDevices([initial])

        let store = ShutterStore(
            device: initial,
            shutterRepository: repository
        ) { _, _ in }

        await repository.syncDevices([updated])
        await settleAsyncState()

        #expect(store.actualStep == .threeQuarter)
        #expect(store.effectiveTargetStep == .threeQuarter)
        #expect(!store.isInFlight)
    }

    @Test
    func selectingCurrentStepDoesNotEmitCommand() async {
        let device = makeShutterDevice(value: 75)
        let repository = makeRepository()
        await repository.syncDevices([device])

        var commandCount = 0
        let store = ShutterStore(
            device: device,
            shutterRepository: repository
        ) { _, _ in
            commandCount += 1
        }

        await settleAsyncState()
        store.select(.threeQuarter)

        #expect(commandCount == 0)
        #expect(store.actualStep == .threeQuarter)
        #expect(!store.isInFlight)
    }

    @Test
    func multipleStoresReceiveSharedRepositoryUpdates() async {
        let initial = makeShutterDevice(value: 0)
        let updated = makeShutterDevice(value: 50)
        let repository = makeRepository()
        await repository.syncDevices([initial])

        let storeA = ShutterStore(
            device: initial,
            shutterRepository: repository
        ) { _, _ in }
        let storeB = ShutterStore(
            device: initial,
            shutterRepository: repository
        ) { _, _ in }

        await repository.setTarget(uniqueId: "shutter-1", targetStep: .half, originStep: .closed)
        await settleAsyncState()

        #expect(storeA.effectiveTargetStep == .half)
        #expect(storeB.effectiveTargetStep == .half)
        #expect(storeA.isInFlight)
        #expect(storeB.isInFlight)

        await repository.syncDevices([updated])
        await settleAsyncState()
        await repository.syncDevices([updated])
        await settleAsyncState()

        #expect(storeA.actualStep == .half)
        #expect(storeB.actualStep == .half)
        #expect(!storeA.isInFlight)
        #expect(!storeB.isInFlight)
    }

    private func makeRepository() -> ShutterRepository {
        let databasePath = TestSupport.temporaryDatabasePath()
        let deviceRepository = DeviceRepository(databasePath: databasePath, log: { _ in })
        return ShutterRepository(databasePath: databasePath, deviceRepository: deviceRepository, log: { _ in })
    }

    private func makeShutterDevice(value: Double) -> DeviceRecord {
        TestSupport.makeDevice(
            uniqueId: "shutter-1",
            name: "Main Shutter",
            usage: "shutter",
            data: ["level": .number(value)],
            metadata: [
                "level": .object([
                    "min": .number(0),
                    "max": .number(100)
                ])
            ]
        )
    }

    private func settleAsyncState() async {
        await Task.yield()
        await Task.yield()
        await Task.yield()
    }
}
