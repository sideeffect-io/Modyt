import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

struct ACKRepositoryTests {
    @Test
    func waitReturnsImmediatelyWhenACKIsAlreadyStored() async throws {
        let testTime = TestTimeDriver()
        let repository = makeRepository(testTime: testTime)
        let transactionId = "tx-immediate"

        await repository.ingest(
            ack: makeACK(statusCode: 200),
            metadata: makeMetadata(transactionId: transactionId)
        )

        try await repository.waitForACK(transactionId: transactionId)

        let secondWaiter = Task {
            try await repository.waitForACK(transactionId: transactionId)
        }

        await settle()
        await testTime.advance(by: .seconds(31))
        await settle()

        do {
            try await secondWaiter.value
            Issue.record("Expected timeout because ACK should be consumed by first waiter")
        } catch let error as ACKRepository.RepositoryError {
            #expect(error == .timeout(transactionId: transactionId))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func waitSuspendsThenResumesWhenACKArrives() async throws {
        let testTime = TestTimeDriver()
        let repository = makeRepository(testTime: testTime)
        let transactionId = "tx-arrival"

        let waiter = Task {
            try await repository.waitForACK(transactionId: transactionId)
            return true
        }

        await settle()

        await repository.ingest(
            ack: makeACK(statusCode: 202),
            metadata: makeMetadata(transactionId: transactionId)
        )

        let didResume = try await waiter.value
        #expect(didResume)
    }

    @Test
    func waitThrowsTimeoutWhenACKNeverArrives() async {
        let testTime = TestTimeDriver()
        let configuration = ACKRepository.Configuration(
            waitTimeout: .seconds(30),
            retention: .seconds(300),
            cleanupInterval: .seconds(300)
        )
        let repository = makeRepository(
            testTime: testTime,
            configuration: configuration
        )
        let transactionId = "tx-timeout"

        let waiter = Task {
            try await repository.waitForACK(transactionId: transactionId)
        }

        await settle()
        await testTime.advance(by: .seconds(31))
        await settle()

        do {
            try await waiter.value
            Issue.record("Expected timeout error for \(transactionId)")
        } catch let error as ACKRepository.RepositoryError {
            #expect(error == .timeout(transactionId: transactionId))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func waitForMultipleResumesWhenAllACKsArrive() async throws {
        let testTime = TestTimeDriver()
        let repository = makeRepository(testTime: testTime)
        let firstTransactionId = "tx-multi-first"
        let secondTransactionId = "tx-multi-second"

        let waiter = Task {
            try await repository.waitForACK(transactionIds: [
                firstTransactionId,
                secondTransactionId
            ])
            return true
        }

        await settle()

        await repository.ingest(
            ack: makeACK(statusCode: 202),
            metadata: makeMetadata(transactionId: secondTransactionId)
        )

        await settle()

        await repository.ingest(
            ack: makeACK(statusCode: 200),
            metadata: makeMetadata(transactionId: firstTransactionId)
        )

        #expect(try await waiter.value)
    }

    @Test
    func waitForMultipleStartsWaitersConcurrently() async {
        let testTime = TestTimeDriver()
        let configuration = ACKRepository.Configuration(
            waitTimeout: .seconds(30),
            retention: .seconds(300),
            cleanupInterval: .seconds(300)
        )
        let repository = makeRepository(
            testTime: testTime,
            configuration: configuration
        )
        let firstTransactionId = "tx-concurrent-first"
        let secondTransactionId = "tx-concurrent-second"

        let waiter = Task {
            try await repository.waitForACK(transactionIds: [
                firstTransactionId,
                secondTransactionId
            ])
        }

        let completionFlag = CompletionFlag()
        Task {
            _ = await waiter.result
            await completionFlag.markCompleted()
        }

        await settle()
        await testTime.advance(by: .seconds(20))
        await settle()

        await repository.ingest(
            ack: makeACK(statusCode: 200),
            metadata: makeMetadata(transactionId: firstTransactionId)
        )

        await settle()
        await testTime.advance(by: .seconds(11))
        await settle(cycles: 16)

        #expect(await completionFlag.isCompleted())

        do {
            try await waiter.value
            Issue.record("Expected timeout for second transaction id")
        } catch let error as ACKRepository.RepositoryError {
            #expect(error == .timeout(transactionId: secondTransactionId))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func duplicateACKRefreshesStoredTimestamp() async throws {
        let testTime = TestTimeDriver()
        let configuration = ACKRepository.Configuration(
            waitTimeout: .seconds(5),
            retention: .seconds(100),
            cleanupInterval: .seconds(10)
        )
        let repository = makeRepository(
            testTime: testTime,
            configuration: configuration
        )
        let transactionId = "tx-refresh"

        await repository.startIfNeeded()
        await repository.ingest(
            ack: makeACK(statusCode: 200),
            metadata: makeMetadata(transactionId: transactionId)
        )

        await testTime.advance(by: .seconds(80))
        await settle()

        await repository.ingest(
            ack: makeACK(statusCode: 201),
            metadata: makeMetadata(transactionId: transactionId)
        )

        await testTime.advance(by: .seconds(40))
        await settle()

        try await repository.waitForACK(transactionId: transactionId)
    }

    @Test
    func cleanupEvictsOldACKs() async {
        let testTime = TestTimeDriver()
        let configuration = ACKRepository.Configuration(
            waitTimeout: .seconds(5),
            retention: .seconds(100),
            cleanupInterval: .seconds(10)
        )
        let repository = makeRepository(
            testTime: testTime,
            configuration: configuration
        )
        let transactionId = "tx-evict"

        await repository.startIfNeeded()
        await repository.ingest(
            ack: makeACK(statusCode: 200),
            metadata: makeMetadata(transactionId: transactionId)
        )

        await testTime.advance(by: .seconds(120))
        await settle()

        let waiter = Task {
            try await repository.waitForACK(transactionId: transactionId)
        }

        await settle()
        await testTime.advance(by: .seconds(6))
        await settle()

        do {
            try await waiter.value
            Issue.record("Expected timeout after cleanup eviction")
        } catch let error as ACKRepository.RepositoryError {
            #expect(error == .timeout(transactionId: transactionId))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    @Test
    func cleanupKeepsFreshACKs() async throws {
        let testTime = TestTimeDriver()
        let configuration = ACKRepository.Configuration(
            waitTimeout: .seconds(5),
            retention: .seconds(100),
            cleanupInterval: .seconds(10)
        )
        let repository = makeRepository(
            testTime: testTime,
            configuration: configuration
        )
        let transactionId = "tx-fresh"

        await repository.startIfNeeded()
        await repository.ingest(
            ack: makeACK(statusCode: 200),
            metadata: makeMetadata(transactionId: transactionId)
        )

        await testTime.advance(by: .seconds(50))
        await settle()

        try await repository.waitForACK(transactionId: transactionId)
    }

    @Test
    func routerIngestsACKIntoACKRepository() async throws {
        let testTime = TestTimeDriver()
        let ackRepository = makeRepository(testTime: testTime)
        let databasePath = temporarySQLitePath()
        defer {
            try? FileManager.default.removeItem(atPath: databasePath)
        }

        let router = TydomMessageRepositoryRouter(
            deviceRepository: DeviceRepository.makeDeviceRepository(databasePath: databasePath),
            groupRepository: GroupRepository.makeGroupRepository(databasePath: databasePath),
            sceneRepository: SceneRepository.makeSceneRepository(databasePath: databasePath),
            ackRepository: ackRepository
        )
        let transactionId = "tx-router"
        let waiter = Task {
            try await ackRepository.waitForACK(transactionId: transactionId)
            return true
        }

        await settle()

        await router.ingest(
            .ack(
                makeACK(statusCode: 200),
                metadata: makeMetadata(transactionId: transactionId, uriOrigin: "/scenarios/12")
            )
        )

        #expect(try await waiter.value)
    }

    @Test
    func ackWithoutTransactionIdIsIgnored() async {
        let testTime = TestTimeDriver()
        let configuration = ACKRepository.Configuration(
            waitTimeout: .seconds(3),
            retention: .seconds(100),
            cleanupInterval: .seconds(10)
        )
        let repository = makeRepository(
            testTime: testTime,
            configuration: configuration
        )
        let transactionId = "tx-missing-id"

        let waiter = Task {
            try await repository.waitForACK(transactionId: transactionId)
        }

        await settle()
        await repository.ingest(
            ack: makeACK(statusCode: 200),
            metadata: makeMetadata(transactionId: nil)
        )
        await testTime.advance(by: .seconds(4))
        await settle()

        do {
            try await waiter.value
            Issue.record("Expected timeout when transaction id is missing")
        } catch let error as ACKRepository.RepositoryError {
            #expect(error == .timeout(transactionId: transactionId))
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }

    private func makeRepository(
        testTime: TestTimeDriver,
        configuration: ACKRepository.Configuration = .init()
    ) -> ACKRepository {
        ACKRepository(
            configuration: configuration,
            dependencies: .init(
                now: { await testTime.now() },
                sleep: { try await testTime.sleep(for: $0) },
                log: { _ in }
            )
        )
    }

    private func makeACK(statusCode: Int) -> TydomAck {
        TydomAck(
            statusCode: statusCode,
            reason: nil,
            headers: [:]
        )
    }

    private func makeMetadata(
        transactionId: String?,
        uriOrigin: String = "/test"
    ) -> TydomMessageMetadata {
        let raw = TydomRawMessage(
            payload: Data(),
            frame: nil,
            uriOrigin: uriOrigin,
            transactionId: transactionId,
            parseError: nil
        )

        return TydomMessageMetadata(
            raw: raw,
            uriOrigin: uriOrigin,
            transactionId: transactionId,
            body: nil,
            bodyJSON: nil
        )
    }

    private func temporarySQLitePath() -> String {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ack-repository-tests", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        return directory
            .appendingPathComponent("\(UUID().uuidString).sqlite")
            .path
    }

    private func settle(cycles: Int = 8) async {
        for _ in 0..<cycles {
            await Task.yield()
        }
    }
}

private actor TestTimeDriver {
    private struct SleepRequest {
        let id: UUID
        let deadline: Date
        let order: UInt64
        let continuation: CheckedContinuation<Void, Error>
    }

    private var nowDate: Date
    private var pendingSleepsByID: [UUID: SleepRequest] = [:]
    private var orderSeed: UInt64 = 0

    init(now: Date = Date(timeIntervalSince1970: 0)) {
        self.nowDate = now
    }

    func now() -> Date {
        nowDate
    }

    func sleep(for duration: Duration) async throws {
        guard duration > .zero else { return }
        try Task.checkCancellation()

        let requestID = UUID()
        let deadline = nowDate.addingTimeInterval(duration.timeInterval)
        let order = orderSeed
        orderSeed += 1

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if Task.isCancelled {
                    continuation.resume(throwing: CancellationError())
                    return
                }

                pendingSleepsByID[requestID] = SleepRequest(
                    id: requestID,
                    deadline: deadline,
                    order: order,
                    continuation: continuation
                )
            }
        } onCancel: {
            Task {
                await self.cancelSleep(id: requestID)
            }
        }
    }

    func advance(by duration: Duration) {
        guard duration > .zero else { return }
        nowDate = nowDate.addingTimeInterval(duration.timeInterval)

        let dueRequests = pendingSleepsByID.values
            .filter { $0.deadline <= nowDate }
            .sorted { lhs, rhs in
                if lhs.deadline != rhs.deadline {
                    return lhs.deadline < rhs.deadline
                }
                return lhs.order < rhs.order
            }

        for request in dueRequests {
            pendingSleepsByID.removeValue(forKey: request.id)
            request.continuation.resume()
        }
    }

    private func cancelSleep(id: UUID) {
        guard let request = pendingSleepsByID.removeValue(forKey: id) else {
            return
        }
        request.continuation.resume(throwing: CancellationError())
    }
}

private actor CompletionFlag {
    private var didComplete = false

    func markCompleted() {
        didComplete = true
    }

    func isCompleted() -> Bool {
        didComplete
    }
}

private extension Duration {
    var timeInterval: TimeInterval {
        let components = self.components
        let seconds = TimeInterval(components.seconds)
        let attoseconds = TimeInterval(components.attoseconds)
        return seconds + (attoseconds / 1_000_000_000_000_000_000)
    }
}
