import Foundation
import Testing
@testable import DeltaDoreClient

@Test func pollScheduler_pollOnceScheduledSendsWhenActive() async {
    // Given
    let recorder = CommandRecorder()
    let activity = ActivityFlag(initial: true)
    let sleepGate = SleepGate()
    let scheduler = TydomMessagePollScheduler(
        send: { command in await recorder.record(command) },
        isActive: { await activity.isActive() },
        sleep: { nanoseconds in try await sleepGate.sleep(nanoseconds) }
    )

    // When
    await scheduler.schedule(urls: ["/a", "/b"], intervalSeconds: 60)
    let initialCount = await recorder.count()

    await scheduler.pollOnceScheduled()
    await spinUntil { await recorder.count() >= initialCount + 2 }
    let afterCount = await recorder.count()

    // Then
    #expect(afterCount >= initialCount + 2)
}

@Test func pollScheduler_respectsInactiveFlag() async {
    // Given
    let recorder = CommandRecorder()
    let activity = ActivityFlag(initial: false)
    let sleepGate = SleepGate()
    let scheduler = TydomMessagePollScheduler(
        send: { command in await recorder.record(command) },
        isActive: { await activity.isActive() },
        sleep: { nanoseconds in try await sleepGate.sleep(nanoseconds) }
    )

    // When
    await scheduler.schedule(urls: ["/a"], intervalSeconds: 60)
    await spinUntil { await recorder.count() > 0 }
    let scheduledCount = await recorder.count()

    await scheduler.pollOnceScheduled()
    await spinUntil { await recorder.count() > scheduledCount }
    let afterCount = await recorder.count()

    // Then
    #expect(scheduledCount == 0)
    #expect(afterCount == 0)
}

private actor CommandRecorder {
    private var commands: [TydomCommand] = []

    func record(_ command: TydomCommand) {
        commands.append(command)
    }

    func count() -> Int {
        commands.count
    }
}

private actor ActivityFlag {
    private var value: Bool

    init(initial: Bool) {
        self.value = initial
    }

    func isActive() -> Bool {
        value
    }
}

private actor SleepGate {
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func sleep(_ nanoseconds: UInt64) async throws {
        _ = nanoseconds
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func releaseOne() {
        if waiters.isEmpty == false {
            let continuation = waiters.removeFirst()
            continuation.resume()
        }
    }
}

private func spinUntil(_ condition: @escaping @Sendable () async -> Bool) async {
    for _ in 0..<20 {
        if await condition() {
            return
        }
        await Task.yield()
    }
}
