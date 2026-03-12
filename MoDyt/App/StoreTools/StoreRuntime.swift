import Foundation

@MainActor
func replaceTask(
    _ task: inout Task<Void, Never>?,
    with newTask: Task<Void, Never>
) {
    task?.cancel()
    task = newTask
}

@MainActor
func cancelTask(_ task: inout Task<Void, Never>?) {
    task?.cancel()
    task = nil
}

func makeTrackedEventTask<Event: Sendable>(
    operation: @escaping @Sendable () async -> Event?,
    onEvent: @escaping @MainActor @Sendable (Event) -> Void,
    onFinish: @escaping @MainActor @Sendable () -> Void = {}
) -> Task<Void, Never> {
    Task {
        let event = await operation()
        guard !Task.isCancelled else {
            await onFinish()
            return
        }
        if let event {
            await onEvent(event)
        }
        await onFinish()
    }
}

func makeTrackedStreamTask<Event: Sendable>(
    operation: @escaping @Sendable () async -> AsyncStream<Event>,
    onEvent: @escaping @MainActor @Sendable (Event) -> Void,
    onFinish: @escaping @MainActor @Sendable () -> Void = {}
) -> Task<Void, Never> {
    Task {
        let stream = await operation()
        for await event in stream {
            guard !Task.isCancelled else {
                await onFinish()
                return
            }
            await onEvent(event)
        }
        await onFinish()
    }
}

func launchFireAndForgetTask(
    _ operation: @escaping @Sendable () async -> Void
) {
    Task {
        await operation()
    }
}

func makeEventStream<Element: Sendable, Event: Sendable>(
    from source: any AsyncSequence<Element, Never> & Sendable,
    map: @escaping @Sendable (Element) -> Event?
) -> AsyncStream<Event> {
    AsyncStream { continuation in
        let task = Task {
            for await element in source {
                guard !Task.isCancelled else { break }
                if let event = map(element) {
                    continuation.yield(event)
                }
            }
            continuation.finish()
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
