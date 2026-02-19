import Foundation

actor TydomPostPutPollingController {
    struct Configuration: Sendable, Equatable {
        let intervalNanoseconds: UInt64
        let maxDurationNanoseconds: UInt64
        let onlyWhenActive: Bool
        let isEnabled: Bool

        init(
            intervalSeconds: Int = 3,
            durationSeconds: Int = 60,
            onlyWhenActive: Bool = true
        ) {
            self.isEnabled = intervalSeconds > 0 && durationSeconds > 0
            self.intervalNanoseconds = UInt64(max(intervalSeconds, 1)) * 1_000_000_000
            self.maxDurationNanoseconds = UInt64(max(durationSeconds, 1)) * 1_000_000_000
            self.onlyWhenActive = onlyWhenActive
        }
    }

    struct Dependencies: Sendable {
        let isActive: @Sendable () async -> Bool
        let sleep: @Sendable (UInt64) async throws -> Void
        let log: @Sendable (String) -> Void

        init(
            isActive: @escaping @Sendable () async -> Bool = { true },
            sleep: @escaping @Sendable (UInt64) async throws -> Void = { try await Task.sleep(nanoseconds: $0) },
            log: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.isActive = isActive
            self.sleep = sleep
            self.log = log
        }
    }

    struct Target: Sendable, Equatable {
        let deviceId: String
        let endpointId: String

        var uniqueId: String {
            "\(endpointId)_\(deviceId)"
        }

        var path: String {
            "/devices/\(deviceId)/endpoints/\(endpointId)/data"
        }
    }

    private struct Entry {
        let target: Target
        let task: Task<Void, Never>
    }

    private let configuration: Configuration
    private let dependencies: Dependencies
    private var entries: [String: Entry] = [:]

    init(
        configuration: Configuration = .init(),
        dependencies: Dependencies = .init()
    ) {
        self.configuration = configuration
        self.dependencies = dependencies
    }

    deinit {
        for entry in entries.values {
            entry.task.cancel()
        }
    }

    func start(
        for target: Target,
        sendPoll: @escaping @Sendable (_ path: String) async -> Void
    ) {
        guard configuration.isEnabled else { return }

        cancelAll(forDeviceId: target.deviceId)

        entries[target.uniqueId] = Entry(
            target: target,
            task: makePollingTask(for: target, sendPoll: sendPoll)
        )

        dependencies.log(
            "Post-PUT polling started uniqueId=\(target.uniqueId) path=\(target.path) duration=\(configuration.maxDurationNanoseconds / 1_000_000_000)s"
        )
    }

    func stopAll() {
        for entry in entries.values {
            entry.task.cancel()
        }
        entries.removeAll()
    }

    func activeTargetUniqueIds() -> [String] {
        Array(entries.keys)
    }

    func isActive(uniqueId: String) -> Bool {
        entries[uniqueId] != nil
    }

    private func makePollingTask(
        for target: Target,
        sendPoll: @escaping @Sendable (_ path: String) async -> Void
    ) -> Task<Void, Never> {
        let configuration = self.configuration
        let isActive = dependencies.isActive
        let sleep = dependencies.sleep

        return Task { [weak self] in
            var elapsedNanoseconds: UInt64 = 0

            while !Task.isCancelled && elapsedNanoseconds < configuration.maxDurationNanoseconds {
                if configuration.onlyWhenActive {
                    let active = await isActive()
                    if active == false {
                        do {
                            try await sleep(configuration.intervalNanoseconds)
                        } catch {
                            break
                        }
                        elapsedNanoseconds += configuration.intervalNanoseconds
                        continue
                    }
                }

                await sendPoll(target.path)

                do {
                    try await sleep(configuration.intervalNanoseconds)
                } catch {
                    break
                }
                elapsedNanoseconds += configuration.intervalNanoseconds
            }

            guard !Task.isCancelled else { return }
            guard elapsedNanoseconds >= configuration.maxDurationNanoseconds else { return }
            await self?.completePolling(forUniqueId: target.uniqueId)
        }
    }

    private func completePolling(forUniqueId uniqueId: String) {
        guard let entry = entries.removeValue(forKey: uniqueId) else { return }
        entry.task.cancel()
        dependencies.log("Post-PUT polling stopped uniqueId=\(uniqueId) reason=timeout")
    }

    private func cancelAll(forDeviceId deviceId: String) {
        let uniqueIds = entries
            .filter { $0.value.target.deviceId == deviceId }
            .map(\.key)

        for uniqueId in uniqueIds {
            guard let entry = entries.removeValue(forKey: uniqueId) else { continue }
            entry.task.cancel()
            dependencies.log("Post-PUT polling stopped uniqueId=\(uniqueId) reason=replaced")
        }
    }
}

extension TydomPostPutPollingController {
    static func target(fromOutgoingRequest text: String) -> Target? {
        target(fromOutgoingRequestData: Data(text.utf8))
    }

    static func target(fromOutgoingRequestData data: Data) -> Target? {
        guard case .success(let frame) = TydomHTTPParser().parse(data) else { return nil }
        guard case .request(let request) = frame else { return nil }
        guard request.method.caseInsensitiveCompare("PUT") == .orderedSame else { return nil }

        return target(fromPath: request.path)
    }

    private static func target(fromPath path: String) -> Target? {
        let requestPath = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? path
        let components = requestPath.split(separator: "/").map(String.init)
        guard components.count == 5 else { return nil }
        guard components[0] == "devices" else { return nil }
        guard components[2] == "endpoints" else { return nil }
        guard components[4] == "data" else { return nil }
        guard components[1].isEmpty == false else { return nil }
        guard components[3].isEmpty == false else { return nil }

        return Target(deviceId: components[1], endpointId: components[3])
    }
}
