import Foundation
import DeltaDoreClient
import MoDytCore

struct AppEnvironment {
    let connect: @Sendable (ConnectRequest, @escaping @Sendable ([SiteInfo]) async -> Int?) async throws -> DeltaDoreClient.ConnectionSession
    let disconnect: @Sendable () async -> Void
    let setAppActive: @Sendable (Bool) async -> Void
    let sendDeviceCommand: @Sendable (DeviceSummary) async throws -> Void
    let startIngestion: @Sendable () async -> Void
    let stopIngestion: @Sendable () async -> Void
    let loadDevices: @Sendable () async throws -> [DeviceSummary]
    let loadLayout: @Sendable () async throws -> [DashboardPlacement]
    let persistFavorite: @Sendable (String, Bool) async throws -> Void
    let persistLayout: @Sendable ([DashboardPlacement]) async throws -> Void
    let changes: @Sendable () async -> AsyncStream<DatabaseChange>
}

extension AppEnvironment {
    static func live(
        database: DatabaseStore,
        connection: ConnectionCoordinator,
        ingestor: MessageIngestor,
        emit: @escaping @MainActor @Sendable (AppEvent) async -> Void
    ) -> AppEnvironment {
        AppEnvironment(
            connect: { request, selectSiteIndex in
                let options = DeltaDoreOptionsBuilder.build(from: request)
                return try await connection.connect(options: options) { sites in
                    let siteInfos = sites.map { site in
                        SiteInfo(
                            id: site.id,
                            name: site.name,
                            gateways: site.gateways.map { gateway in
                                SiteInfo.GatewayInfo(mac: gateway.mac, name: gateway.name)
                            }
                        )
                    }
                    await emit(.siteSelectionRequested(siteInfos))
                    return await selectSiteIndex(siteInfos)
                }
            },
            disconnect: {
                await connection.disconnect()
            },
            setAppActive: { isActive in
                await connection.setAppActive(isActive)
            },
            sendDeviceCommand: { device in
                let data = try await database.stateData(for: device.id) ?? [:]
                let command = DeviceCommandMapper.makeToggleCommand(from: device, data: data)
                if let command {
                    try await connection.send(command)
                }
            },
            startIngestion: {
                if let stream = await connection.stream() {
                    await ingestor.start(stream: stream, database: database)
                }
            },
            stopIngestion: {
                await ingestor.stop()
            },
            loadDevices: {
                let snapshots = try await database.listDeviceSnapshots()
                let layout = try await database.listLayout()
                let favorites = try await database.listFavorites()
                return DeviceSummaryBuilder.build(
                    snapshots: snapshots,
                    favorites: favorites,
                    layout: layout
                )
            },
            loadLayout: {
                let layout = try await database.listLayout()
                return layout.map { placement in
                    DashboardPlacement(
                        deviceId: placement.deviceKey,
                        row: placement.row,
                        column: placement.column,
                        span: placement.span
                    )
                }
            },
            persistFavorite: { deviceId, isFavorite in
                try await database.setFavorite(deviceKey: deviceId, isFavorite: isFavorite)
            },
            persistLayout: { layout in
                let records = layout.map { placement in
                    DashboardLayoutRecord(
                        deviceKey: placement.deviceId,
                        row: placement.row,
                        column: placement.column,
                        span: placement.span
                    )
                }
                try await database.setLayout(records)
            },
            changes: {
                await database.changes()
            }
        )
    }
}

nonisolated private enum DeltaDoreOptionsBuilder {
    nonisolated static func build(from request: ConnectRequest) -> DeltaDoreClient.Options {
        switch request {
        case .auto:
            return DeltaDoreClient.Options(
                mode: .auto,
                cloudCredentials: nil,
                bonjourServices: [],
                forceRemote: shouldForceRemote(expert: ExpertOptions())
            )
        case .credentials(let form):
            let credentials = form.email.isEmpty || form.password.isEmpty
                ? nil
                : TydomConnection.CloudCredentials(email: form.email, password: form.password)

            let mode = resolveMode(from: form.expert)

            return DeltaDoreClient.Options(
                mode: mode,
                localHostOverride: normalized(form.expert.localHostOverride),
                mac: normalized(form.expert.macOverride),
                cloudCredentials: credentials,
                bonjourServices: [],
                forceRemote: shouldForceRemote(expert: form.expert)
            )
        }
    }

    nonisolated static func resolveMode(from expert: ExpertOptions) -> DeltaDoreClient.Options.Mode {
        guard expert.isEnabled else { return .auto }
        switch expert.connectionMode {
        case .auto:
            return .auto
        case .forceLocal:
            return .local
        case .forceRemote:
            return .remote
        }
    }

    nonisolated static func normalized(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    nonisolated static func shouldForceRemote(expert: ExpertOptions) -> Bool {
        guard expert.isEnabled == false || expert.connectionMode == .auto else {
            return expert.connectionMode == .forceRemote
        }
        return false
    }
}
