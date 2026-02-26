import Foundation
import DeltaDoreClient

actor ACKRepository {
    enum RepositoryError: Swift.Error, Equatable {
        case timeout(transactionId: String)
    }

    struct ACKMessage: Sendable, Equatable {
        let ack: TydomAck
        let metadata: TydomMessageMetadata
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
        let message: ACKMessage
        let createdAt: Date
    }

    private struct PendingWaiter {
        let continuation: CheckedContinuation<ACKMessage, Swift.Error>
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

        let message = ACKMessage(ack: ack, metadata: metadata)
        let createdAt = await dependencies.now()
        if resumeWaiter(for: transactionId, message: message) == false {
            acksByTransactionId[transactionId] = StoredACK(
                message: message,
                createdAt: createdAt
            )
        }
    }

    func waitForACK(transactionId: String) async throws {
        _ = try await waitForACKMessage(transactionId: transactionId)
    }

    func waitForACKMessage(
        transactionId: String,
        timeout: Duration? = nil
    ) async throws -> ACKMessage {
        if let storedACK = acksByTransactionId.removeValue(forKey: transactionId) {
            return storedACK.message
        }

        let waitTimeout = timeout ?? configuration.waitTimeout
        let sleep = dependencies.sleep

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<ACKMessage, Swift.Error>) in
                guard pendingWaitersByTransactionId[transactionId] == nil else {
                    dependencies.log("ACKRepository already has a waiter for transaction id '\(transactionId)'")
                    continuation.resume(throwing: CancellationError())
                    return
                }

                let timeoutTask = Task { [weak self] in
                    do {
                        try await sleep(waitTimeout)
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

    func waitForACK(transactionIds: [String]) async throws {
        try await withThrowingTaskGroup(of: Void.self) { group in
            for transactionId in transactionIds {
                group.addTask { [self, transactionId] in
                    try await self.waitForACK(transactionId: transactionId)
                }
            }

            try await group.waitForAll()
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

    private func resumeWaiter(for transactionId: String, message: ACKMessage) -> Bool {
        guard let waiter = pendingWaitersByTransactionId.removeValue(forKey: transactionId) else {
            return false
        }

        waiter.timeoutTask.cancel()
        waiter.continuation.resume(returning: message)
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
