import Foundation

actor SiteSelectionGate {
    private var continuation: CheckedContinuation<Int?, Never>?
    private var pendingIndex: Int?

    func waitForSelection() async -> Int? {
        if let pendingIndex {
            self.pendingIndex = nil
            return pendingIndex
        }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func provideSelection(_ index: Int) {
        if let continuation {
            continuation.resume(returning: index)
            self.continuation = nil
        } else {
            pendingIndex = index
        }
    }

    func cancel() {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
