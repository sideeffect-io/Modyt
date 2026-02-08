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

final class BufferedStreamBox<Element> {
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

func settleAsyncState(iterations: Int = 8) async {
    for _ in 0..<iterations {
        await Task.yield()
    }
}
