import Foundation
import DeltaDoreClient

actor ACKRepository {
    enum RepositoryError: Swift.Error, Equatable {
        case timeout(transactionId: String)
    }

    struct Configuration: Sendable {
        var waitTimeout: Duration = .seconds(30)
        var retention: Duration = .seconds(300)
        var cleanupInterval: Duration = .seconds(300)
    }

    struct Dependencies: Sendable {
        var now: @Sendable () async -> Date
        var sleep: @Sendable (Duration) async throws -> Void
        var log: @Sendable (String) -> Void

        static let live = Self(
            now: { Date() },
            sleep: { try await Task.sleep(for: $0) },
            log: { _ in }
        )
    }

    private struct StoredACK: Sendable, Equatable {
        let ack: TydomAck
        let metadata: TydomMessageMetadata
        let createdAt: Date
    }

    private struct PendingWaiter {
        let continuation: CheckedContinuation<Void, Swift.Error>
        let timeoutTask: Task<Void, Never>
    }

    private let configuration: Configuration
    private let dependencies: Dependencies

    private var acksByTransactionId: [String: StoredACK] = [:]
    private var pendingWaitersByTransactionId: [String: PendingWaiter] = [:]
    private var cleanupTask: Task<Void, Never>?

    init(
        configuration: Configuration = .init(),
        dependencies: Dependencies = .live
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
    }

    deinit {
        cleanupTask?.cancel()
        cleanupTask = nil
        for waiter in pendingWaitersByTransactionId.values {
            waiter.timeoutTask.cancel()
            waiter.continuation.resume(throwing: CancellationError())
        }
    }

    func startIfNeeded() {
        guard cleanupTask == nil else { return }

        let interval = configuration.cleanupInterval
        let sleep = dependencies.sleep

        cleanupTask = Task { [weak self] in
            while !Task.isCancelled {
                do {
                    try await sleep(interval)
                } catch {
                    return
                }
                await self?.evictExpiredACKs()
            }
        }
    }

    func ingest(ack: TydomAck, metadata: TydomMessageMetadata) async {
        guard let transactionId = metadata.transactionId?.trimmingCharacters(in: .whitespacesAndNewlines),
              transactionId.isEmpty == false else {
            dependencies.log("ACKRepository ignored ACK without transaction id")
            return
        }

        let createdAt = await dependencies.now()
        if resumeWaiter(for: transactionId) == false {
            acksByTransactionId[transactionId] = StoredACK(
                ack: ack,
                metadata: metadata,
                createdAt: createdAt
            )
        }
    }

    func waitForACK(transactionId: String) async throws {
        if acksByTransactionId.removeValue(forKey: transactionId) != nil {
            return
        }

        let timeout = configuration.waitTimeout
        let sleep = dependencies.sleep

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Swift.Error>) in
                guard pendingWaitersByTransactionId[transactionId] == nil else {
                    dependencies.log("ACKRepository already has a waiter for transaction id '\(transactionId)'")
                    continuation.resume(throwing: CancellationError())
                    return
                }

                let timeoutTask = Task { [weak self] in
                    do {
                        try await sleep(timeout)
                    } catch {
                        return
                    }

                    await self?.timeoutWaiter(transactionId: transactionId)
                }

                pendingWaitersByTransactionId[transactionId] = PendingWaiter(
                    continuation: continuation,
                    timeoutTask: timeoutTask
                )
            }
        } onCancel: {
            Task { [transactionId] in
                await self.cancelWaiter(transactionId: transactionId)
            }
        }
    }

    private func timeoutWaiter(transactionId: String) {
        guard let waiter = pendingWaitersByTransactionId.removeValue(forKey: transactionId) else {
            return
        }
        waiter.continuation.resume(throwing: RepositoryError.timeout(transactionId: transactionId))
    }

    private func cancelWaiter(transactionId: String) {
        guard let waiter = pendingWaitersByTransactionId.removeValue(forKey: transactionId) else {
            return
        }
        waiter.timeoutTask.cancel()
        waiter.continuation.resume(throwing: CancellationError())
    }

    private func resumeWaiter(for transactionId: String) -> Bool {
        guard let waiter = pendingWaitersByTransactionId.removeValue(forKey: transactionId) else {
            return false
        }

        waiter.timeoutTask.cancel()
        waiter.continuation.resume()
        return true
    }

    private func evictExpiredACKs() async {
        let referenceDate = await dependencies.now()
        let retention = configuration.retention.timeInterval

        acksByTransactionId = acksByTransactionId.filter { _, entry in
            let expirationDate = entry.createdAt.addingTimeInterval(retention)
            return expirationDate >= referenceDate
        }
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
