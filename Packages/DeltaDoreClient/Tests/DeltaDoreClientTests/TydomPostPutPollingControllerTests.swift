import Foundation
import Testing
@testable import DeltaDoreClient

@Test func postPutPollingController_extractsTargetFromPutRequest() {
    // Given
    let request = """
    PUT /devices/1757536112/endpoints/1757536112/data HTTP/1.1\r
    Content-Length: 34\r
    Content-Type: application/json; charset=UTF-8\r
    Transac-Id: 0\r
    \r
    [{"name":"position","value":50}]\r
    \r
    """

    // When
    let target = TydomPostPutPollingController.target(fromOutgoingRequest: request)

    // Then
    #expect(target?.deviceId == "1757536112")
    #expect(target?.endpointId == "1757536112")
    #expect(target?.uniqueId == "1757536112_1757536112")
    #expect(target?.path == "/devices/1757536112/endpoints/1757536112/data")
}

@Test func postPutPollingController_ignoresNonPutRequest() {
    // Given
    let request = """
    GET /devices/1757536112/endpoints/1757536112/data HTTP/1.1\r
    Content-Length: 0\r
    Content-Type: application/json; charset=UTF-8\r
    Transac-Id: 0\r
    \r
    """

    // When
    let target = TydomPostPutPollingController.target(fromOutgoingRequest: request)

    // Then
    #expect(target == nil)
}

@Test func postPutPollingController_stopsAfterDuration() async {
    // Given
    let pollProbe = PollProbe()
    let controller = TydomPostPutPollingController(
        configuration: .init(intervalSeconds: 1, durationSeconds: 3, onlyWhenActive: false),
        dependencies: .init(
            isActive: { true },
            sleep: { _ in
                return
            }
        )
    )
    let target = TydomPostPutPollingController.Target(
        deviceId: "1757536112",
        endpointId: "1757536112"
    )
    await controller.start(for: target) { path in
        await pollProbe.record(path)
    }

    let pollsCompleted = await waitUntil(timeout: 0.5) {
        await pollProbe.count() >= 3
    }

    let pollingStopped = await waitUntil(timeout: 0.5) {
        await controller.activeTargetUniqueIds().isEmpty
    }

    // Then
    #expect(pollsCompleted)
    #expect(pollingStopped)
    #expect(await pollProbe.count() == 3)
}

@Test func postPutPollingController_replacesTaskForSameDevice() async {
    // Given
    let pollProbe = PollProbe()
    let controller = TydomPostPutPollingController(
        configuration: .init(intervalSeconds: 1, durationSeconds: 60, onlyWhenActive: false),
        dependencies: .init(
            isActive: { true },
            sleep: { _ in
                try await Task.sleep(nanoseconds: 100_000_000)
            }
        )
    )
    let firstTarget = TydomPostPutPollingController.Target(
        deviceId: "1757536112",
        endpointId: "1"
    )
    let secondTarget = TydomPostPutPollingController.Target(
        deviceId: "1757536112",
        endpointId: "2"
    )

    // When
    await controller.start(for: firstTarget) { path in
        await pollProbe.record(path)
    }
    let firstStarted = await waitUntil(timeout: 0.5) {
        await pollProbe.count(for: firstTarget.path) >= 1
    }

    await controller.start(for: secondTarget) { path in
        await pollProbe.record(path)
    }
    let secondStarted = await waitUntil(timeout: 0.5) {
        await pollProbe.count(for: secondTarget.path) >= 1
    }

    try? await Task.sleep(nanoseconds: 300_000_000)
    let firstCountAfterReplace = await pollProbe.count(for: firstTarget.path)
    let secondCountAfterReplace = await pollProbe.count(for: secondTarget.path)

    // Then
    #expect(firstStarted)
    #expect(secondStarted)
    #expect(firstCountAfterReplace == 1)
    #expect(secondCountAfterReplace >= 2)
}

private func waitUntil(
    timeout: TimeInterval,
    condition: @escaping @Sendable () async -> Bool
) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return true
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    return await condition()
}

private actor PollProbe {
    private var paths: [String] = []

    func record(_ path: String) {
        paths.append(path)
    }

    func count() -> Int {
        paths.count
    }

    func count(for path: String) -> Int {
        paths.filter { $0 == path }.count
    }
}
