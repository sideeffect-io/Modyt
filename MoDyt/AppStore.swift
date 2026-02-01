import Foundation
import Observation
import DeltaDoreClient
import MoDytCore

@MainActor
@Observable
final class AppStore {
    var state: AppState

    private var environment: AppEnvironment?
    private let siteGate = SiteSelectionGate()
    private var effectTask: Task<Void, Never>?
    private var changeTask: Task<Void, Never>?

    init() {
        self.state = AppState.initial()
        bootstrap()
    }

    func send(_ event: AppEvent) {
        let transition = AppReducer.reduce(state: state, event: event)
        state = transition.state
        transition.effects.forEach(enqueue)
    }

    private func enqueue(_ effect: AppEffect) {
        if case .provideSiteSelection(let index) = effect {
            Task { [siteGate] in
                await siteGate.provideSelection(index)
            }
            return
        }

        let previous = effectTask
        effectTask = Task { [weak self] in
            if let previous {
                _ = await previous.result
            }
            await self?.handle(effect)
        }
    }

    private func handle(_ effect: AppEffect) async {
        guard let environment else { return }

        switch effect {
        case .connect(let request):
            do {
                let session = try await connectWithTimeout(request: request, environment: environment)
                _ = session
                send(.connectSucceeded)
            } catch {
                send(.connectFailed(error.localizedDescription))
            }

        case .disconnect:
            await environment.stopIngestion()
            await environment.disconnect()
            send(.disconnected)

        case .loadInitialData:
            await reloadData(using: environment)

        case .sendDeviceCommand(let device):
            do {
                try await environment.sendDeviceCommand(device)
            } catch {
                // Keep UI responsive; errors will be reflected by gateway state updates.
            }

        case .persistFavorite(let deviceId, let isFavorite):
            do {
                try await environment.persistFavorite(deviceId, isFavorite)
            } catch {
                // Ignore persistence errors; UI will re-sync on next reload.
            }

        case .persistLayout(let layout):
            do {
                try await environment.persistLayout(layout)
            } catch {
                // Ignore persistence errors; UI will re-sync on next reload.
            }

        case .provideSiteSelection(let index):
            await siteGate.provideSelection(index)

        case .setAppActive(let isActive):
            await environment.setAppActive(isActive)

        case .startMessageStream:
            await environment.startIngestion()

        case .stopMessageStream:
            await environment.stopIngestion()
        }
    }

    private func bootstrap() {
        Task { @MainActor in
            do {
                let database = try await DatabaseStore.live()
                let connection = ConnectionCoordinator()
                let ingestor = MessageIngestor()
                let env = AppEnvironment.live(
                    database: database,
                    connection: connection,
                    ingestor: ingestor,
                    emit: { [weak self] event in
                        self?.send(event)
                    }
                )
                self.environment = env
                self.startChangeListener(environment: env)
                self.send(.onAppear)
            } catch {
                self.state.errorMessage = error.localizedDescription
            }
        }
    }

    private func startChangeListener(environment: AppEnvironment) {
        changeTask?.cancel()
        changeTask = Task { [weak self] in
            guard let self else { return }
            let changes = await environment.changes()
            for await _ in changes {
                await MainActor.run {
                    self.send(.errorCleared)
                }
                await self.reloadData(using: environment)
            }
        }
    }

    private func reloadData(using environment: AppEnvironment) async {
        do {
            let devices = try await environment.loadDevices()
            let layout = try await environment.loadLayout()
            send(.devicesLoaded(devices))
            send(.dashboardLayoutLoaded(layout))
        } catch {
            // Ignore load errors; keep last known state.
        }
    }

    private func connectWithTimeout(
        request: ConnectRequest,
        environment: AppEnvironment
    ) async throws -> DeltaDoreClient.ConnectionSession {
        try await withThrowingTaskGroup(of: DeltaDoreClient.ConnectionSession.self) { group in
            group.addTask { [siteGate] in
                try await environment.connect(request) { _ in
                    await siteGate.waitForSelection()
                }
            }
            group.addTask {
                try await Task.sleep(nanoseconds: 60_000_000_000)
                throw TimeoutError()
            }

            defer { group.cancelAll() }
            guard let result = try await group.next() else {
                throw TimeoutError()
            }
            return result
        }
    }
}

private struct TimeoutError: LocalizedError {
    var errorDescription: String? {
        "Connection timed out. Check your network and credentials, then try again."
    }
}
