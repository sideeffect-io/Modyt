import Foundation

actor TestRecorder<Value: Sendable> {
    private(set) var values: [Value] = []

    func record(_ value: Value) {
        values.append(value)
    }
}

actor Counter {
    private(set) var value = 0

    func increment() {
        value += 1
    }
}

final class LockedCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var rawValue = 0

    func increment() {
        lock.lock()
        rawValue += 1
        lock.unlock()
    }

    var value: Int {
        lock.lock()
        let result = rawValue
        lock.unlock()
        return result
    }
}

final class BufferedStreamBox<Element: Sendable>: @unchecked Sendable {
    private var pending: [Element] = []
    private var continuation: AsyncStream<Element>.Continuation?

    lazy var stream: AsyncStream<Element> = {
        AsyncStream<Element> { continuation in
            self.continuation = continuation
            for element in pending {
                continuation.yield(element)
            }
            pending.removeAll()
        }
    }()

    func yield(_ element: Element) {
        if let continuation {
            continuation.yield(element)
            return
        }
        pending.append(element)
    }

    func finish() {
        continuation?.finish()
    }
}

func waitUntil(
    timeout: Duration = .seconds(2),
    pollingInterval: Duration = .milliseconds(10),
    condition: @escaping @MainActor () async -> Bool
) async -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: timeout)

    while clock.now < deadline {
        if await condition() {
            return true
        }
        do {
            try await Task.sleep(for: pollingInterval)
        } catch {
            return false
        }
    }

    return await condition()
}
