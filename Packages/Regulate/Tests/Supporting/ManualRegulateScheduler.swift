import Foundation
@testable import Regulate

final class ManualRegulateScheduler: @unchecked Sendable {
  private struct PendingSleep {
    let id: UUID
    let deadlineNanoseconds: UInt64
    let order: UInt64
    let continuation: CheckedContinuation<Void, Error>
  }

  private let lock = NSLock()
  private var nowNanoseconds: UInt64 = 0
  private var nextOrder: UInt64 = 0
  private var pendingSleeps: [UUID: PendingSleep] = [:]

  var scheduler: RegulateScheduler {
    RegulateScheduler(
      now: { [weak self] in
        self?.currentDispatchTime() ?? DispatchTime(uptimeNanoseconds: 0)
      },
      sleep: { [weak self] nanoseconds in
        guard let self else { return }
        try await self.sleep(nanoseconds: nanoseconds)
      }
    )
  }

  func advance(by interval: DispatchTimeInterval) {
    let delta = interval.nanoseconds
    guard delta > 0 else { return }

    let dueSleeps: [PendingSleep]
    lock.lock()
    nowNanoseconds += delta
    dueSleeps = pendingSleeps.values
      .filter { $0.deadlineNanoseconds <= nowNanoseconds }
      .sorted { lhs, rhs in
        if lhs.deadlineNanoseconds != rhs.deadlineNanoseconds {
          return lhs.deadlineNanoseconds < rhs.deadlineNanoseconds
        }
        return lhs.order < rhs.order
      }
    for pendingSleep in dueSleeps {
      pendingSleeps.removeValue(forKey: pendingSleep.id)
    }
    lock.unlock()

    dueSleeps.forEach { $0.continuation.resume() }
  }

  private func currentDispatchTime() -> DispatchTime {
    lock.lock()
    defer { lock.unlock() }
    return DispatchTime(uptimeNanoseconds: nowNanoseconds)
  }

  private func sleep(nanoseconds: UInt64) async throws {
    guard nanoseconds > 0 else { return }
    try Task.checkCancellation()

    let id = UUID()
    let reservation = reserveSleep(nanoseconds: nanoseconds)

    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
          return
        }

        registerSleep(
          id: id,
          reservation: reservation,
          continuation: continuation
        )
      }
    } onCancel: {
      self.cancelSleep(id: id)
    }
  }

  private func cancelSleep(id: UUID) {
    let continuation: CheckedContinuation<Void, Error>?

    lock.lock()
    continuation = pendingSleeps.removeValue(forKey: id)?.continuation
    lock.unlock()

    continuation?.resume(throwing: CancellationError())
  }

  private func reserveSleep(nanoseconds: UInt64) -> (deadlineNanoseconds: UInt64, order: UInt64) {
    lock.lock()
    defer { lock.unlock() }
    let reservation = (
      deadlineNanoseconds: nowNanoseconds + nanoseconds,
      order: nextOrder
    )
    nextOrder += 1
    return reservation
  }

  private func registerSleep(
    id: UUID,
    reservation: (deadlineNanoseconds: UInt64, order: UInt64),
    continuation: CheckedContinuation<Void, Error>
  ) {
    lock.lock()
    defer { lock.unlock() }
    pendingSleeps[id] = PendingSleep(
      id: id,
      deadlineNanoseconds: reservation.deadlineNanoseconds,
      order: reservation.order,
      continuation: continuation
    )
  }
}

func settleRegulateTasks(cycles: Int = 8) async {
  for _ in 0..<cycles {
    await Task.yield()
  }
}
