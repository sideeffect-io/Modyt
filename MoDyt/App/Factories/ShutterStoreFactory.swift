import SwiftUI
import DeltaDoreClient

struct ShutterStoreFactory {
    let make: @MainActor ([String]) -> ShutterStore

    static func live(environment: AppEnvironment) -> ShutterStoreFactory {
        ShutterStoreFactory { shutterUniqueIds in
            ShutterStore(
                shutterUniqueIds: shutterUniqueIds,
                dependencies: .init(
                    observePositions: { shutterUniqueIds in
                        let ids = shutterUniqueIds.joined(separator: ",")
                        environment.log("ShutterTrace factory observe-start ids=\(ids)")
                        return await environment.newShutterRepository.observeShuttersPositions(
                            uniqueIds: shutterUniqueIds
                        )
                    },
                    sendTargetPosition: { shutterUniqueIds, target in
                        guard shutterUniqueIds.isEmpty == false else {
                            environment.log("Shutter target skipped: no shutter ids provided")
                            return
                        }
                        let ids = shutterUniqueIds.joined(separator: ",")
                        environment.log("Shutter target requested ids=\(ids) target=\(target)")
                        await environment.newShutterRepository.setShuttersTarget(uniqueIds: shutterUniqueIds, targetPosition: target)
                        for uniqueId in shutterUniqueIds {
                            let command = await Self.command(
                                for: uniqueId,
                                target: target,
                                repository: environment.repository
                            )
                            environment.log(
                                "ShutterTrace factory command uniqueId=\(uniqueId) target=\(target) key=\(command.key) value=\(command.value.traceString)"
                            )
                            await environment.sendDeviceCommand(
                                uniqueId,
                                command.key,
                                command.value
                            )
                        }
                    },
                    syncTargetCache: { shutterUniqueIds, target in
                        guard shutterUniqueIds.isEmpty == false else {
                            environment.log("Shutter target sync skipped: no shutter ids provided")
                            return
                        }
                        let ids = shutterUniqueIds.joined(separator: ",")
                        environment.log("Shutter target sync ids=\(ids) target=\(target)")
                        await environment.newShutterRepository.setShuttersTarget(
                            uniqueIds: shutterUniqueIds,
                            targetPosition: target
                        )
                    },
                    startCompletionTimer: { onFinished in
                        Task {
                            do {
                                try await Task.sleep(
                                    nanoseconds: Self.completionTimeoutNanoseconds
                                )
                            } catch {
                                return
                            }
                            await MainActor.run {
                                onFinished()
                            }
                        }
                    },
                    log: environment.log
                )
            )
        }
    }

    private static let completionTimeoutNanoseconds: UInt64 = 60_000_000_000

    private static func command(
        for uniqueId: String,
        target: Int,
        repository: DeviceRepository
    ) async -> (key: String, value: JSONValue) {
        let descriptor = await repository
            .device(uniqueId: uniqueId)?
            .primaryControlDescriptor()
        return mappedCommand(targetPosition: target, descriptor: descriptor)
    }

    static func mappedCommand(
        targetPosition: Int,
        descriptor: DeviceControlDescriptor?
    ) -> (key: String, value: JSONValue) {
        let clampedTarget = max(0, min(targetPosition, 100))
        guard let descriptor else {
            return ("level", .number(Double(clampedTarget)))
        }
        switch descriptor.kind {
        case .slider:
            let normalizedTarget = Double(clampedTarget) / 100
            let mappedValue = descriptor.range.lowerBound
                + (descriptor.range.upperBound - descriptor.range.lowerBound) * normalizedTarget
            return (descriptor.key, .number(mappedValue))
        case .toggle:
            return (descriptor.key, .bool(clampedTarget > 0))
        }
    }
}

private struct ShutterStoreFactoryKey: EnvironmentKey {
    static var defaultValue: ShutterStoreFactory {
        ShutterStoreFactory.live(environment: .live())
    }
}

private extension JSONValue {
    var traceString: String {
        switch self {
        case .string(let text):
            return "\"\(text)\""
        case .number(let number):
            if number.rounded(.towardZero) == number {
                return String(Int(number))
            }
            return String(number)
        case .bool(let flag):
            return flag ? "true" : "false"
        case .null:
            return "null"
        case .object(let value):
            return "object(keys:\(value.keys.sorted()))"
        case .array(let value):
            return "array(count:\(value.count))"
        }
    }
}

extension EnvironmentValues {
    var shutterStoreFactory: ShutterStoreFactory {
        get { self[ShutterStoreFactoryKey.self] }
        set { self[ShutterStoreFactoryKey.self] = newValue }
    }
}
