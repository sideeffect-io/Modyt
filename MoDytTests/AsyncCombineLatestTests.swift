import Testing
@testable import MoDyt

private enum AsyncCombineLatestTestError: Error, Equatable, Sendable {
    case boom
}

private func captureThrownError(
    _ body: () throws -> Void
) -> (any Error)? {
    do {
        try body()
        return nil
    } catch {
        return error
    }
}

struct AsyncCombineLatestSequenceTests {
    @Test
    func twoSequenceCombinesBufferedValuesAndFinishes() async throws {
        let numbers = TestAsyncStreamBox<Int>()
        let letters = TestAsyncStreamBox<String>()
        let iterator = TestAsyncIteratorBox(combineLatest(numbers.stream, letters.stream))

        let firstTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.yield(1)
        letters.yield("a")

        let first = try #require(try await firstTask.value)
        #expect(first.0 == 1)
        #expect(first.1 == "a")

        let secondTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.yield(2)

        let second = try #require(try await secondTask.value)
        #expect(second.0 == 2)
        #expect(second.1 == "a")

        letters.yield("b")
        await testSettle()

        let buffered = try #require(try await iterator.next())
        #expect(buffered.0 == 2)
        #expect(buffered.1 == "b")

        let completionTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.finish()
        letters.finish()

        #expect(try await completionTask.value == nil)
        #expect(try await iterator.next() == nil)
    }

    @Test
    func threeSequenceCombinesBufferedValuesAndFinishes() async throws {
        let numbers = TestAsyncStreamBox<Int>()
        let letters = TestAsyncStreamBox<String>()
        let flags = TestAsyncStreamBox<Bool>()
        let iterator = TestAsyncIteratorBox(
            combineLatest(numbers.stream, letters.stream, flags.stream)
        )

        let firstTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.yield(1)
        letters.yield("a")
        flags.yield(true)

        let first = try #require(try await firstTask.value)
        #expect(first.0 == 1)
        #expect(first.1 == "a")
        #expect(first.2 == true)

        let secondTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.yield(2)

        let second = try #require(try await secondTask.value)
        #expect(second.0 == 2)
        #expect(second.1 == "a")
        #expect(second.2 == true)

        flags.yield(false)
        await testSettle()

        let buffered = try #require(try await iterator.next())
        #expect(buffered.0 == 2)
        #expect(buffered.1 == "a")
        #expect(buffered.2 == false)

        let completionTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.finish()
        letters.finish()
        flags.finish()

        #expect(try await completionTask.value == nil)
        #expect(try await iterator.next() == nil)
    }

    @Test
    func twoSequenceReturnsNilWhenAnUpstreamFinishesBeforeTheInitialTuple() async throws {
        let numbers = TestAsyncStreamBox<Int>()
        let letters = TestAsyncStreamBox<String>()
        let iterator = TestAsyncIteratorBox(combineLatest(numbers.stream, letters.stream))

        let nextTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.finish()

        #expect(try await nextTask.value == nil)
        #expect(try await iterator.next() == nil)
    }

    @Test
    func twoSequenceThrowsWhenAnUpstreamFailsBeforeTheInitialTuple() async {
        let numbers = TestAsyncThrowingStreamBox<Int>()
        let letters = TestAsyncThrowingStreamBox<String>()
        let iterator = TestAsyncIteratorBox(combineLatest(numbers.stream, letters.stream))

        let nextTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.yield(1)
        letters.fail(AsyncCombineLatestTestError.boom)

        do {
            _ = try await nextTask.value
            #expect(Bool(false))
        } catch {
            #expect((error as? AsyncCombineLatestTestError) == .boom)
        }
    }

    @Test
    func twoSequenceRethrowsStoredLateFailureOnNextDemand() async throws {
        let numbers = TestAsyncThrowingStreamBox<Int>()
        let letters = TestAsyncThrowingStreamBox<String>()
        let iterator = TestAsyncIteratorBox(combineLatest(numbers.stream, letters.stream))

        let firstTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.yield(1)
        letters.yield("a")

        let first = try #require(try await firstTask.value)
        #expect(first.0 == 1)
        #expect(first.1 == "a")

        let secondTask = Task {
            try await iterator.next()
        }
        await testSettle()

        numbers.yield(2)

        let second = try #require(try await secondTask.value)
        #expect(second.0 == 2)
        #expect(second.1 == "a")

        letters.fail(AsyncCombineLatestTestError.boom)
        await testSettle(cycles: 20)

        do {
            _ = try await iterator.next()
            #expect(Bool(false))
        } catch {
            #expect((error as? AsyncCombineLatestTestError) == .boom)
        }
    }

    @Test
    func twoSequenceHandlesConsumerCancellation() async {
        let numbers = TestAsyncStreamBox<Int>()
        let letters = TestAsyncStreamBox<String>()
        let sequence = combineLatest(numbers.stream, letters.stream)

        let nextTask = Task {
            var iterator = sequence.makeAsyncIterator()
            return await iterator.next()
        }
        await testSettle()

        nextTask.cancel()

        let value = await nextTask.value
        #expect(value == nil)
    }
}

struct AsyncCombineLatestSupportTests {
    @Test
    func managedCriticalStateMutatesSafely() {
        let state = ManagedCriticalState(0)

        let first = state.withCriticalRegion { value in
            value += 1
            return value
        }

        let second = state.withLock { value in
            value += 4
            return value
        }

        #expect(first == 1)
        #expect(second == 5)
        #expect(state.withCriticalRegion { $0 } == 5)
    }

    @Test
    func rethrowHelpersReturnValuesAndRethrowFailures() throws {
        let success: Result<Int, any Error> = .success(42)
        #expect(try success._rethrowGet() == 42)

        let failure: Result<Int, any Error> = .failure(AsyncCombineLatestTestError.boom)

        do {
            _ = try failure._rethrowGet()
            #expect(Bool(false))
        } catch {
            #expect((error as? AsyncCombineLatestTestError) == .boom)
        }

        #expect((captureThrownError { try failure._rethrowError() } as? AsyncCombineLatestTestError) == .boom)
    }
}
