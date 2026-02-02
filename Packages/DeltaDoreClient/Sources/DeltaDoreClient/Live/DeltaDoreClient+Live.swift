import Foundation

public extension DeltaDoreClient.Dependencies {
    static func live(
        credentialService: String = "io.sideeffect.deltadoreclient.gateway",
        gatewayMacService: String = "io.sideeffect.deltadoreclient.gateway-mac",
        cloudCredentialService: String = "io.sideeffect.deltadoreclient.cloud-credentials",
        remoteHost: String = "mediation.tydom.com",
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> DeltaDoreClient.Dependencies {
        let environment = TydomConnectionResolver.Environment.live(
            credentialService: credentialService,
            gatewayMacService: gatewayMacService,
            cloudCredentialService: cloudCredentialService,
            remoteHost: remoteHost,
            now: now
        )
        let resolver = TydomConnectionResolver(environment: environment)

        let buildSession: @Sendable (TydomConnectionResolver.Resolution) async throws -> DeltaDoreClient.ConnectionSession = { resolution in
            let connection = TydomConnection(
                configuration: resolution.configuration,
                onDisconnect: resolution.onDisconnect
            )
            try await connection.connect()
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
                let resolverOptions = TydomConnectionResolver.Options(
                    mode: mapStoredMode(options.mode),
                    credentialPolicy: .useStoredDataOnly
                )
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
        now: @escaping @Sendable () -> Date = { Date() }
    ) -> DeltaDoreClient {
        DeltaDoreClient(
            dependencies: .live(
                credentialService: credentialService,
                gatewayMacService: gatewayMacService,
                cloudCredentialService: cloudCredentialService,
                remoteHost: remoteHost,
                now: now
            )
        )
    }
}
