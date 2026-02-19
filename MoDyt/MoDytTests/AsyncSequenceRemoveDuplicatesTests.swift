import Testing
@testable import MoDyt

struct AsyncSequenceRemoveDuplicatesTests {
    @Test
    func removeDuplicatesSkipsConsecutiveValues() async {
        var continuation: AsyncStream<Int>.Continuation?
        let source = AsyncStream<Int> { streamContinuation in
            continuation = streamContinuation
        }
        let recorder = TestRecorder<Int>()

        let observationTask = Task {
            for await value in source.removeDuplicates() {
                await recorder.record(value)
            }
        }

        continuation?.yield(1)
        continuation?.yield(1)
        continuation?.yield(2)
        continuation?.yield(2)
        continuation?.yield(3)
        continuation?.finish()

        _ = await observationTask.result

        let values = await recorder.values
        #expect(values == [1, 2, 3])
    }
}
