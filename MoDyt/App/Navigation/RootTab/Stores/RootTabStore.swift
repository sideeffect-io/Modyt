import Foundation
import Observation
import DeltaDoreClient

struct RootTabState: Sendable, Equatable {
    var isAppActive: Bool

    static let initial = RootTabState(isAppActive: true)
}

enum RootTabEvent: Sendable {
    case onStart
    case setAppActive(Bool)
}

enum RootTabEffect: Sendable, Equatable {
    case preparePersistence
    case startMessageStream
    case sendBootstrapRequests
    case setAppActive(Bool)
}

enum RootTabReducer {
    static func reduce(
        state: RootTabState,
        event: RootTabEvent
    ) -> (RootTabState, [RootTabEffect]) {
        var state = state
        var effects: [RootTabEffect] = []

        switch event {
        case .onStart:
            effects = [
                .preparePersistence,
                .startMessageStream,
                .sendBootstrapRequests,
                .setAppActive(state.isAppActive)
            ]

        case .setAppActive(let isActive):
            state.isAppActive = isActive
            effects = [.setAppActive(isActive)]
        }

        return (state, effects)
    }
}

@Observable
@MainActor
final class RootTabStore {
    struct Dependencies {
        let log: @Sendable (String) -> Void
        let preparePersistence: @Sendable () async -> Void
        let decodeMessages: @Sendable () async -> AsyncStream<TydomMessage>
        let applyMessage: @Sendable (TydomMessage) async -> Void
        let sendText: @Sendable (String) async -> Void
        let setAppActive: @Sendable (Bool) async -> Void
    }

    private(set) var state: RootTabState

    private let messageTask = TaskHandle()
    private let worker: Worker

    init(dependencies: Dependencies) {
        self.state = .initial
        self.worker = Worker(
            log: dependencies.log,
            preparePersistence: dependencies.preparePersistence,
            decodeMessages: dependencies.decodeMessages,
            applyMessage: dependencies.applyMessage,
            sendText: dependencies.sendText,
            setAppActive: dependencies.setAppActive
        )
    }

    func send(_ event: RootTabEvent) {
        let (nextState, effects) = RootTabReducer.reduce(state: state, event: event)
        state = nextState
        handle(effects)
    }

    private func handle(_ effects: [RootTabEffect]) {
        for effect in effects {
            handle(effect)
        }
    }

    private func handle(_ effect: RootTabEffect) {
        switch effect {
        case .preparePersistence:
            Task { [worker] in
                await worker.preparePersistence()
            }

        case .startMessageStream:
            guard messageTask.task == nil else { return }
            messageTask.task = Task { [worker] in
                await worker.streamMessages()
            }

        case .sendBootstrapRequests:
            Task { [worker] in
                await worker.sendBootstrapRequests()
            }

        case .setAppActive(let isActive):
            Task { [worker] in
                await worker.setAppActive(isActive)
            }
        }
    }

    private actor Worker {
        private let log: @Sendable (String) -> Void
        private let preparePersistenceAction: @Sendable () async -> Void
        private let decodeMessages: @Sendable () async -> AsyncStream<TydomMessage>
        private let applyMessage: @Sendable (TydomMessage) async -> Void
        private let sendText: @Sendable (String) async -> Void
        private let setAppActiveAction: @Sendable (Bool) async -> Void

        init(
            log: @escaping @Sendable (String) -> Void,
            preparePersistence: @escaping @Sendable () async -> Void,
            decodeMessages: @escaping @Sendable () async -> AsyncStream<TydomMessage>,
            applyMessage: @escaping @Sendable (TydomMessage) async -> Void,
            sendText: @escaping @Sendable (String) async -> Void,
            setAppActive: @escaping @Sendable (Bool) async -> Void
        ) {
            self.log = log
            self.preparePersistenceAction = preparePersistence
            self.decodeMessages = decodeMessages
            self.applyMessage = applyMessage
            self.sendText = sendText
            self.setAppActiveAction = setAppActive
        }

        func preparePersistence() async {
            await preparePersistenceAction()
        }

        func streamMessages() async {
            log("Message stream started")
            let messages = await decodeMessages()
            for await message in messages {
                guard !Task.isCancelled else { return }
                log("Message received \(describe(message))")
                await applyMessage(message)
            }
            log("Message stream finished")
        }

        func sendBootstrapRequests() async {
            log("Send configs-file")
            await sendText(TydomCommand.configsFile().request)
            log("Send devices-meta")
            await sendText(TydomCommand.devicesMeta().request)
            log("Send devices-cmeta")
            await sendText(TydomCommand.devicesCmeta().request)
            log("Send devices-data")
            await sendText(TydomCommand.devicesData().request)
            log("Send refresh-all")
            await sendText(TydomCommand.refreshAll().request)
        }

        func setAppActive(_ isActive: Bool) async {
            await setAppActiveAction(isActive)
        }
    }
}

private final class TaskHandle {
    var task: Task<Void, Never>? {
        didSet { oldValue?.cancel() }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }

    deinit {
        task?.cancel()
    }
}

private func describe(_ message: TydomMessage) -> String {
    switch message {
    case .devices(let devices, let transactionId):
        return "devices count=\(devices.count) tx=\(transactionId ?? "nil")"
    case .gatewayInfo(_, let transactionId):
        return "gatewayInfo tx=\(transactionId ?? "nil")"
    case .scenarios(let scenarios, let transactionId):
        return "scenarios count=\(scenarios.count) tx=\(transactionId ?? "nil")"
    case .groups(_, let transactionId):
        return "groups tx=\(transactionId ?? "nil")"
    case .moments(_, let transactionId):
        return "moments tx=\(transactionId ?? "nil")"
    case .areas(let areas, let transactionId):
        return "areas count=\(areas.count) tx=\(transactionId ?? "nil")"
    case .raw(let raw):
        let origin = raw.uriOrigin ?? "nil"
        let tx = raw.transactionId ?? "nil"
        let bodyCount = raw.frame?.body?.count ?? 0
        let preview = raw.frame?.body
            .flatMap { data in
                String(data: data.prefix(200), encoding: .isoLatin1)
                    ?? String(decoding: data.prefix(200), as: UTF8.self)
            } ?? ""
        let suffix = preview.isEmpty ? "" : " bodyPreview=\(preview)"
        return "raw bytes=\(raw.payload.count) uri=\(origin) tx=\(tx) body=\(bodyCount)\(suffix)"
    }
}
