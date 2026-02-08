import Foundation
import DeltaDoreClient
@testable import MoDyt

enum TestError: Error {
    case expectedFailure
}

enum TestSupport {
    static func makeConnection() -> TydomConnection {
        TydomConnection(
            configuration: .init(
                mode: .remote(),
                mac: "AA:BB:CC:DD:EE:FF"
            )
        )
    }

    static func makeEnvironment(
        inspectFlow: @escaping @Sendable () async -> DeltaDoreClient.ConnectionFlowStatus = { .connectWithNewCredentials },
        clearStoredData: @escaping @Sendable () async -> Void = {}
    ) -> AppEnvironment {
        let client = DeltaDoreClient(
            dependencies: .init(
                inspectFlow: inspectFlow,
                connectStored: { _ in
                    throw TestError.expectedFailure
                },
                connectNew: { _, _ in
                    throw TestError.expectedFailure
                },
                listSites: { _ in [] },
                listSitesPayload: { _ in Data() },
                clearStoredData: clearStoredData
            )
        )

        let databasePath = temporaryDatabasePath()
        let repository = DeviceRepository(databasePath: databasePath, log: { _ in })
        let shutterRepository = ShutterRepository(
            databasePath: databasePath,
            deviceRepository: repository,
            log: { _ in }
        )
        return AppEnvironment(
            client: client,
            repository: repository,
            shutterRepository: shutterRepository,
            setOnDidDisconnect: { _ in },
            requestRefreshAll: {},
            sendDeviceCommand: { _, _, _ in },
            requestDisconnect: {},
            now: Date.init,
            log: { _ in }
        )
    }

    static func temporaryDatabasePath() -> String {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("MoDytTests-\(UUID().uuidString).sqlite")
            .path
    }

    static func makeDevice(
        uniqueId: String,
        name: String,
        usage: String,
        isFavorite: Bool = false,
        dashboardOrder: Int? = nil,
        data: [String: JSONValue] = [:],
        metadata: [String: JSONValue]? = nil
        ) -> DeviceRecord {
            DeviceRecord(
                uniqueId: uniqueId,
                deviceId: 1,
                endpointId: 1,
                name: name,
            usage: usage,
            kind: DeviceGroup.from(usage: usage).rawValue,
            data: data,
            metadata: metadata,
            isFavorite: isFavorite,
            favoriteOrder: dashboardOrder,
            dashboardOrder: dashboardOrder,
            updatedAt: Date()
        )
    }
}
