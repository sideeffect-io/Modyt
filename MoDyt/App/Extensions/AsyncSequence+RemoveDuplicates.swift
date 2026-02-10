import Foundation

extension AsyncSequence where Failure == Never, Element: Equatable & Sendable {
    func removeDuplicates() -> AsyncRemoveDuplicatesSequence<Self> {
        removeDuplicates(by: ==)
    }
}

extension AsyncSequence {
    func removeDuplicates(
        by isDuplicate: @escaping @Sendable (Element, Element) async -> Bool
    ) -> AsyncRemoveDuplicatesSequence<Self> {
        AsyncRemoveDuplicatesSequence(self, predicate: isDuplicate)
    }
}

struct AsyncRemoveDuplicatesSequence<Base: AsyncSequence>: AsyncSequence {
    typealias Element = Base.Element
    typealias Failure = Base.Failure

    struct Iterator: AsyncIteratorProtocol {
        var iterator: Base.AsyncIterator
        let predicate: @Sendable (Element, Element) async -> Bool
        var last: Element?

        mutating func next() async rethrows -> Element? {
            guard let last else {
                self.last = try await iterator.next()
                return self.last
            }

            while let element = try await iterator.next() {
                if await !predicate(last, element) {
                    self.last = element
                    return element
                }
            }

            return nil
        }
    }

    let base: Base
    let predicate: @Sendable (Element, Element) async -> Bool

    init(
        _ base: Base,
        predicate: @escaping @Sendable (Element, Element) async -> Bool
    ) {
        self.base = base
        self.predicate = predicate
    }

    func makeAsyncIterator() -> Iterator {
        Iterator(
            iterator: base.makeAsyncIterator(),
            predicate: predicate
        )
    }
}

extension AsyncRemoveDuplicatesSequence: Sendable where Base: Sendable, Base.Element: Sendable {}
