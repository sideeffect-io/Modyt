import Foundation

actor TydomMessageEffectExecutor {
    struct Dependencies: Sendable {
        let sendCommand: @Sendable (TydomCommand) async throws -> Void
        let onPong: @Sendable () async -> Void
        let onCDataReplyChunk: @Sendable (TydomCDataReplyChunk) async -> Void
        let log: @Sendable (String) -> Void

        init(
            sendCommand: @escaping @Sendable (TydomCommand) async throws -> Void,
            onPong: @escaping @Sendable () async -> Void = {},
            onCDataReplyChunk: @escaping @Sendable (TydomCDataReplyChunk) async -> Void = { _ in },
            log: @escaping @Sendable (String) -> Void = { _ in }
        ) {
            self.sendCommand = sendCommand
            self.onPong = onPong
            self.onCDataReplyChunk = onCDataReplyChunk
            self.log = log
        }
    }

    private let continuation: AsyncStream<TydomMessageEffect>.Continuation
    private let workerTask: Task<Void, Never>
    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        let (stream, continuation) = AsyncStream<TydomMessageEffect>.makeStream()
        self.continuation = continuation
        self.dependencies = dependencies
        self.workerTask = Task {
            for await effect in stream {
                await Self.handle(effect, dependencies: dependencies)
            }
        }
    }

    deinit {
        continuation.finish()
        workerTask.cancel()
    }

    func enqueue(_ effects: [TydomMessageEffect]) {
        for effect in effects {
            continuation.yield(effect)
        }
    }

    private static func handle(_ effect: TydomMessageEffect, dependencies: Dependencies) async {
        switch effect {
        case .sendCommands(let commands):
            for command in commands {
                _ = try? await dependencies.sendCommand(command)
            }
        case .pongReceived:
            await dependencies.onPong()
        case .cdataReplyChunk(let chunk):
            await dependencies.onCDataReplyChunk(chunk)
        }
    }
}
