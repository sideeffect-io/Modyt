import Foundation
import Testing
import DeltaDoreClient
@testable import MoDyt

@MainActor
func testWaitUntil(
    cycles: Int = 40,
    condition: @escaping @MainActor () -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if condition() {
            return true
        }
        await Task.yield()
    }
    return condition()
}

func testWaitUntilAsync(
    cycles: Int = 80,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    for _ in 0..<cycles {
        if await condition() {
            return true
        }
        await Task.yield()
    }
    return await condition()
}

func testSettle(cycles: Int = 8) async {
    for _ in 0..<cycles {
        await Task.yield()
    }
}

func testTemporarySQLitePath(_ directoryName: String) -> String {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent(directoryName, isDirectory: true)
    try? FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
    )
    return directory
        .appendingPathComponent("\(UUID().uuidString).sqlite")
        .path
}

func testFirstValue<S: AsyncSequence & Sendable>(
    from stream: S,
    timeoutNanoseconds: UInt64 = 1_000_000_000
) async -> S.Element? where S.Element: Sendable {
    await withTaskGroup(of: S.Element?.self) { group in
        group.addTask {
            var iterator = stream.makeAsyncIterator()
            do {
                return try await iterator.next()
            } catch {
                return nil
            }
        }

        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return nil
        }

        let first = await group.next() ?? nil
        group.cancelAll()
        return first
    }
}

final class TestAsyncStreamBox<Element: Sendable>: @unchecked Sendable {
    let stream: AsyncStream<Element>

    private let continuation: AsyncStream<Element>.Continuation

    init(
        bufferingPolicy: AsyncStream<Element>.Continuation.BufferingPolicy = .unbounded
    ) {
        var localContinuation: AsyncStream<Element>.Continuation?
        self.stream = AsyncStream(bufferingPolicy: bufferingPolicy) { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ value: Element) {
        continuation.yield(value)
    }

    func finish() {
        continuation.finish()
    }
}

final class TestAsyncThrowingStreamBox<Element: Sendable>: @unchecked Sendable {
    let stream: AsyncThrowingStream<Element, any Error>

    private let continuation: AsyncThrowingStream<Element, any Error>.Continuation

    init() {
        var localContinuation: AsyncThrowingStream<Element, any Error>.Continuation?
        self.stream = AsyncThrowingStream { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!
    }

    func yield(_ value: Element) {
        continuation.yield(value)
    }

    func finish() {
        continuation.finish()
    }

    func fail(_ error: any Error) {
        continuation.finish(throwing: error)
    }
}

final class TestAsyncIteratorBox<Sequence: AsyncSequence & Sendable>: @unchecked Sendable where Sequence.Element: Sendable {
    private struct Request {
        let reply: CheckedContinuation<Result<Sequence.Element?, any Error>, Never>
    }

    private let continuation: AsyncStream<Request>.Continuation
    private let worker: Task<Void, Never>

    init(_ sequence: Sequence) {
        var localContinuation: AsyncStream<Request>.Continuation?
        let requests = AsyncStream<Request> { continuation in
            localContinuation = continuation
        }
        self.continuation = localContinuation!

        self.worker = Task {
            var iterator = sequence.makeAsyncIterator()

            for await request in requests {
                do {
                    request.reply.resume(returning: .success(try await iterator.next()))
                } catch {
                    request.reply.resume(returning: .failure(error))
                }
            }
        }
    }

    deinit {
        continuation.finish()
        worker.cancel()
    }

    func next() async throws -> Sequence.Element? {
        let result = await withCheckedContinuation { continuation in
            self.continuation.yield(.init(reply: continuation))
        }

        return try result.get()
    }
}

actor TestCounter {
    private var count = 0

    func increment() {
        count += 1
    }

    func value() -> Int {
        count
    }
}

actor TestRecorder<Value: Sendable> {
    private var entries: [Value] = []

    func record(_ value: Value) {
        entries.append(value)
    }

    func values() -> [Value] {
        entries
    }
}

func makeTestDevice(
    identifier: DeviceIdentifier = .init(deviceId: 1, endpointId: 1),
    name: String = "Device",
    usage: String = "light",
    kind: String = "light",
    data: [String: JSONValue] = [:],
    metadata: [String: JSONValue]? = nil,
    isFavorite: Bool = false,
    dashboardOrder: Int? = nil,
    shutterTargetPosition: Int? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 1)
) -> Device {
    Device(
        id: identifier,
        deviceId: identifier.deviceId,
        endpointId: identifier.endpointId,
        name: name,
        usage: usage,
        kind: kind,
        data: data,
        metadata: metadata,
        isFavorite: isFavorite,
        dashboardOrder: dashboardOrder,
        shutterTargetPosition: shutterTargetPosition,
        updatedAt: updatedAt
    )
}

func makeTestGroup(
    id: String = "group-1",
    name: String = "Group",
    usage: String = "light",
    picto: String? = nil,
    isGroupUser: Bool = true,
    isGroupAll: Bool = false,
    memberIdentifiers: [DeviceIdentifier] = [],
    isFavorite: Bool = false,
    dashboardOrder: Int? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 1)
) -> Group {
    Group(
        id: id,
        name: name,
        usage: usage,
        picto: picto,
        isGroupUser: isGroupUser,
        isGroupAll: isGroupAll,
        memberIdentifiers: memberIdentifiers,
        isFavorite: isFavorite,
        dashboardOrder: dashboardOrder,
        updatedAt: updatedAt
    )
}

func makeTestScene(
    id: String = "scene-1",
    name: String = "Scene",
    type: String = "user",
    picto: String = "sun.max",
    ruleId: String? = nil,
    payload: [String: JSONValue] = [:],
    isFavorite: Bool = false,
    dashboardOrder: Int? = nil,
    updatedAt: Date = Date(timeIntervalSince1970: 1)
) -> Scene {
    Scene(
        id: id,
        name: name,
        type: type,
        picto: picto,
        ruleId: ruleId,
        payload: payload,
        isFavorite: isFavorite,
        dashboardOrder: dashboardOrder,
        updatedAt: updatedAt
    )
}

func makeTestRepositoryDeviceSection(
    usage: Usage,
    items: [Device]
) -> DeviceTypeSection {
    DeviceTypeSection(usage: usage, items: items)
}

func makeTestACK(statusCode: Int = 200) -> TydomAck {
    TydomAck(statusCode: statusCode, reason: nil, headers: [:])
}

func makeTestMetadata(
    transactionId: String? = nil,
    uriOrigin: String = "/test"
) -> TydomMessageMetadata {
    let raw = TydomRawMessage(
        payload: Data(),
        frame: nil,
        uriOrigin: uriOrigin,
        transactionId: transactionId,
        parseError: nil
    )

    return TydomMessageMetadata(
        raw: raw,
        uriOrigin: uriOrigin,
        transactionId: transactionId,
        body: nil,
        bodyJSON: nil
    )
}
