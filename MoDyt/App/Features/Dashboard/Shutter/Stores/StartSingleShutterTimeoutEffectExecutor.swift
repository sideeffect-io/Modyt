import Foundation

struct StartSingleShutterTimeoutEffectExecutor: Sendable {
    let sleep: @Sendable (Duration) async throws -> Void
    let timeoutDuration: Duration

    init(
        sleep: @escaping @Sendable (Duration) async throws -> Void,
        timeoutDuration: Duration = .seconds(60)
    ) {
        self.sleep = sleep
        self.timeoutDuration = timeoutDuration
    }

    @concurrent
    func callAsFunction() async -> SingleShutterEvent? {
        do {
            try await sleep(timeoutDuration)
            return .timeoutHasExpired
        } catch {
            return nil
        }
    }
}
