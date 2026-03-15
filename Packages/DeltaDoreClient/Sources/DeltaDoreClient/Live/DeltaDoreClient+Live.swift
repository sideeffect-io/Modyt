import Foundation
import OSLog

public extension DeltaDoreClient.Dependencies {
    static func live(
        credentialService: String = "io.sideeffect.deltadoreclient.gateway",
        gatewayMacService: String = "io.sideeffect.deltadoreclient.gateway-mac",
        cloudCredentialService: String = "io.sideeffect.deltadoreclient.cloud-credentials",
        remoteHost: String = "mediation.tydom.com",
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @Sendable (String) -> Void = { message in
#if DEBUG
            Logger(
                subsystem: "io.sideeffect.deltadoreclient",
                category: "Diagnostics"
            )
            .debug("\(message, privacy: .public)")
#endif
        }
    ) -> DeltaDoreClient.Dependencies {
        let environment = TydomConnectionResolver.Environment.live(
            credentialService: credentialService,
            gatewayMacService: gatewayMacService,
            cloudCredentialService: cloudCredentialService,
            remoteHost: remoteHost,
            now: now,
            log: log
        )
        let resolver = TydomConnectionResolver(environment: environment)

        let buildSession: @Sendable (TydomConnectionResolver.Resolution) async throws -> DeltaDoreClient.ConnectionSession = { resolution in
            if let connection = resolution.connection {
                return DeltaDoreClient.ConnectionSession(connection: connection)
            }
            let connection = TydomConnection(
                configuration: resolution.configuration,
                log: log,
                onDisconnect: resolution.onDisconnect
            )
            try await connectAndValidate(
                connection,
                configuration: resolution.configuration
            )
            return DeltaDoreClient.ConnectionSession(connection: connection)
        }

        return DeltaDoreClient.Dependencies(
            inspectFlow: {
                guard let mac = try? await environment.gatewayMacStore.load() else {
                    return .connectWithNewCredentials
                }
                let gatewayId = TydomMac.normalize(mac)
                if let _ = try? await environment.credentialStore.load(gatewayId) {
                    return .connectWithStoredCredentials
                }
                return .connectWithNewCredentials
            },
            connectStored: { options in
                let resolverOptions = makeStoredResolverOptions(for: options.mode)
                let resolution = try await resolver.resolve(resolverOptions)
                return try await buildSession(resolution)
            },
            connectNew: { options, selectSiteIndex in
                let (mode, cloudCredentials, localHostOverride, macOverride) = mapNewMode(options.mode)
                let resolverOptions = TydomConnectionResolver.Options(
                    mode: mode,
                    credentialPolicy: .allowCloudDataFetch,
                    localHostOverride: localHostOverride,
                    macOverride: macOverride,
                    cloudCredentials: cloudCredentials
                )
                let resolution = try await resolver.resolve(
                    resolverOptions,
                    selectSiteIndex: selectSiteIndex
                )
                return try await buildSession(resolution)
            },
            listSites: { credentials in
                try await resolver.listSites(cloudCredentials: credentials)
            },
            listSitesPayload: { credentials in
                try await resolver.listSitesPayload(cloudCredentials: credentials)
            },
            clearStoredData: {
                await resolver.clearPersistedData()
            },
            probeConnection: { connection, timeout in
                await probeConnectionWithRetry(connection, timeout: timeout)
            }
        )
    }
}

public extension DeltaDoreClient {
    static func live(
        credentialService: String = "io.sideeffect.deltadoreclient.gateway",
        gatewayMacService: String = "io.sideeffect.deltadoreclient.gateway-mac",
        cloudCredentialService: String = "io.sideeffect.deltadoreclient.cloud-credentials",
        remoteHost: String = "mediation.tydom.com",
        now: @escaping @Sendable () -> Date = { Date() },
        log: @escaping @Sendable (String) -> Void = { message in
#if DEBUG
            Logger(
                subsystem: "io.sideeffect.deltadoreclient",
                category: "Diagnostics"
            )
            .debug("\(message, privacy: .public)")
#endif
        }
    ) -> DeltaDoreClient {
        DeltaDoreClient(
            dependencies: .live(
                credentialService: credentialService,
                gatewayMacService: gatewayMacService,
                cloudCredentialService: cloudCredentialService,
                remoteHost: remoteHost,
                now: now,
                log: log
            )
        )
    }
}

func makeStoredResolverOptions(
    for mode: DeltaDoreClient.StoredCredentialsFlowOptions.Mode
) -> TydomConnectionResolver.Options {
    let timings: TydomConnectionResolver.Options.Timings
    switch mode {
    case .auto, .forceLocal:
        timings = .storedLocalPreferredFlow
    case .forceRemote:
        timings = .silentStoredFlow
    }

    return TydomConnectionResolver.Options(
        mode: mapStoredMode(mode),
        credentialPolicy: .useStoredDataOnly,
        timings: timings,
        preferFreshLocalDiscovery: mode == .auto
    )
}

private func probeConnectionWithRetry(
    _ connection: TydomConnection,
    timeout: TimeInterval
) async -> Bool {
    let probeTimeout = max(0.2, timeout)
    for attempt in 0..<2 {
        do {
            try await probeConnectionLiveness(
                using: connection,
                timeout: probeTimeout
            )
            return true
        } catch {
            if let connectionError = error as? TydomConnection.ConnectionError,
               connectionError == .notConnected {
                return false
            }
            if attempt == 0 {
                try? await Task.sleep(nanoseconds: 200_000_000)
            }
        }
    }
    return false
}

func connectAndValidate(
    _ connection: TydomConnection,
    configuration: TydomConnection.Configuration
) async throws {
    let validationTimeout = validationTimeout(for: configuration)
    do {
        try await connection.connect(
            startReceiving: false,
            requestTimeout: validationTimeout
        )
        try await connection.waitForWebSocketOpen(timeout: validationTimeout)
        _ = try await connection.pingAndWaitForResponse(timeout: validationTimeout)
        await connection.startStreamingIfNeeded()
    } catch {
        await connection.disconnect(shouldNotifyOnDisconnect: false)
        throw error
    }
}

func validationTimeout(
    for configuration: TydomConnection.Configuration
) -> TimeInterval {
    max(0.5, configuration.timeout)
}
