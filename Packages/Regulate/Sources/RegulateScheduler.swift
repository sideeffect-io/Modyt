import Foundation

public struct RegulateScheduler: Sendable {
  public let now: @Sendable () -> DispatchTime
  public let sleep: @Sendable (UInt64) async throws -> Void

  public init(
    now: @escaping @Sendable () -> DispatchTime = { DispatchTime.now() },
    sleep: @escaping @Sendable (UInt64) async throws -> Void = { nanoseconds in
      try await Task.sleep(nanoseconds: nanoseconds)
    }
  ) {
    self.now = now
    self.sleep = sleep
  }

  public static let live = RegulateScheduler()
}
