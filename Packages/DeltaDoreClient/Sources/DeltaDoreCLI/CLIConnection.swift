import Foundation
import DeltaDoreClient

func runCLI(
    connection: TydomConnection,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async {
    await connection.setAppActive(true)

    let initialPingOk = await send(command: .ping(), connection: connection, stderr: stderr)
    guard initialPingOk else {
        await stderr.writeLine("Connection closed before initial ping.")
        await connection.disconnect()
        return
    }

    let messageTask = Task {
        let stream = await connection.decodedMessages(logger: { message in
            Task { await stderr.writeLine("[polling] \(message)") }
        })
        for await message in stream {
            let output = render(message: message)
            await stdout.writeLine(output)
        }
    }

    await stdout.writeLine("Connected. Type `help` to list commands.")

    inputLoop: for await line in stdinLines() {
        guard let result = parseInputCommand(line) else { continue }
        switch result {
        case .failure(let error):
            await stderr.writeLine(error.message)
        case .success(let command):
            switch command {
            case .help:
                await stdout.writeLine(commandHelpText())
            case .quit:
                break inputLoop
            case .setActive(let isActive):
                await connection.setAppActive(isActive)
                await stdout.writeLine("App active set to \(isActive).")
            case .send(let command):
                await send(command: command, connection: connection, stderr: stderr)
            case .sendMany(let commands):
                for command in commands {
                    await send(command: command, connection: connection, stderr: stderr)
                }
            case .sendRaw(let raw):
                do {
                    try await connection.send(text: raw)
                } catch {
                    await stderr.writeLine("Send failed: \(error)")
                }
            }
        }
    }

    await connection.disconnect()
    messageTask.cancel()
    await stdout.writeLine("Disconnected.")
}

func connectAuto(
    options: AutoOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> TydomConnection? {
    let client = makeClient()
    if options.clearStorage {
        await client.clearStoredData()
        await stderr.writeLine("Cleared stored data.")
    }
    if await handleSiteListingIfNeeded(
        listSites: options.listSites,
        dumpSitesResponse: options.dumpSitesResponse,
        cloudCredentials: options.cloudCredentials,
        client: client,
        stdout: stdout,
        stderr: stderr
    ) {
        return nil
    }

    if options.forceLocal && options.forceRemote {
        await stderr.writeLine("Cannot use --force-local and --force-remote together.")
        return nil
    }

    let flow = await client.inspectConnectionFlow()
    switch flow {
    case .connectWithStoredCredentials:
        let mode = storedMode(forceLocal: options.forceLocal, forceRemote: options.forceRemote)
        do {
            let session = try await client.connectWithStoredCredentials(
                options: .init(mode: mode)
            )
            return session.connection
        } catch {
            await stderr.writeLine("Failed to connect with stored credentials: \(error.localizedDescription)")
            return nil
        }
    case .connectWithNewCredentials:
        guard let cloudCredentials = options.cloudCredentials else {
            await stderr.writeLine("Missing cloud credentials to start new credential flow.")
            return nil
        }
        let mode: DeltaDoreClient.NewCredentialsFlowOptions.Mode
        if options.forceLocal {
            guard let localIP = options.localIP, let localMAC = options.localMAC else {
                await stderr.writeLine("--force-local requires --local-ip and --local-mac.")
                return nil
            }
            mode = .forceLocal(
                cloudCredentials: cloudCredentials,
                localIP: localIP,
                localMAC: localMAC
            )
        } else if options.forceRemote {
            mode = .forceRemote(cloudCredentials: cloudCredentials)
        } else {
            mode = .auto(cloudCredentials: cloudCredentials)
        }

        let selector = siteIndexSelector(
            siteIndex: options.siteIndex,
            stdout: stdout,
            stderr: stderr
        )

        do {
            let session = try await client.connectWithNewCredentials(
                options: .init(mode: mode),
                selectSiteIndex: selector
            )
            return session.connection
        } catch {
            await stderr.writeLine("Failed to connect with new credentials: \(error.localizedDescription)")
            return nil
        }
    }
}

func connectStored(
    options: StoredOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> TydomConnection? {
    let client = makeClient()
    if options.clearStorage {
        await client.clearStoredData()
        await stderr.writeLine("Cleared stored data.")
    }
    if options.forceLocal && options.forceRemote {
        await stderr.writeLine("Cannot use --force-local and --force-remote together.")
        return nil
    }

    let mode = storedMode(forceLocal: options.forceLocal, forceRemote: options.forceRemote)
    do {
        let session = try await client.connectWithStoredCredentials(
            options: .init(mode: mode)
        )
        return session.connection
    } catch {
        await stderr.writeLine("Failed to connect with stored credentials: \(error.localizedDescription)")
        return nil
    }
}

func connectNew(
    options: NewOptions,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> TydomConnection? {
    let client = makeClient()
    if options.clearStorage {
        await client.clearStoredData()
        await stderr.writeLine("Cleared stored data.")
    }
    if await handleSiteListingIfNeeded(
        listSites: options.listSites,
        dumpSitesResponse: options.dumpSitesResponse,
        cloudCredentials: options.cloudCredentials,
        client: client,
        stdout: stdout,
        stderr: stderr
    ) {
        return nil
    }

    guard let cloudCredentials = options.cloudCredentials else {
        await stderr.writeLine("Missing cloud credentials to start new credential flow.")
        return nil
    }

    if options.forceLocal && options.forceRemote {
        await stderr.writeLine("Cannot use --force-local and --force-remote together.")
        return nil
    }

    let mode: DeltaDoreClient.NewCredentialsFlowOptions.Mode
    if options.forceLocal {
        guard let localIP = options.localIP, let localMAC = options.localMAC else {
            await stderr.writeLine("--force-local requires --local-ip and --local-mac.")
            return nil
        }
        mode = .forceLocal(
            cloudCredentials: cloudCredentials,
            localIP: localIP,
            localMAC: localMAC
        )
    } else if options.forceRemote {
        mode = .forceRemote(cloudCredentials: cloudCredentials)
    } else {
        mode = .auto(cloudCredentials: cloudCredentials)
    }

    let selector = siteIndexSelector(
        siteIndex: options.siteIndex,
        stdout: stdout,
        stderr: stderr
    )

    do {
        let session = try await client.connectWithNewCredentials(
            options: .init(mode: mode),
            selectSiteIndex: selector
        )
        return session.connection
    } catch {
        await stderr.writeLine("Failed to connect with new credentials: \(error.localizedDescription)")
        return nil
    }
}

private func storedMode(
    forceLocal: Bool,
    forceRemote: Bool
) -> DeltaDoreClient.StoredCredentialsFlowOptions.Mode {
    if forceLocal { return .forceLocal }
    if forceRemote { return .forceRemote }
    return .auto
}

private func siteIndexSelector(
    siteIndex: Int?,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) -> DeltaDoreClient.SiteIndexSelector? {
    if let siteIndex {
        return { _ in siteIndex }
    }
    return { sites in
        await chooseSiteIndex(sites, stdout: stdout, stderr: stderr)
    }
}

private func makeClient() -> DeltaDoreClient {
    DeltaDoreClient.live(
        credentialService: "io.sideeffect.deltadoreclient.cli",
        gatewayMacService: "io.sideeffect.deltadoreclient.cli.gateway-mac",
        cloudCredentialService: "io.sideeffect.deltadoreclient.cli.cloud-credentials"
    )
}

private func handleSiteListingIfNeeded(
    listSites: Bool,
    dumpSitesResponse: Bool,
    cloudCredentials: TydomConnection.CloudCredentials?,
    client: DeltaDoreClient,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter
) async -> Bool {
    if dumpSitesResponse {
        guard let cloudCredentials else {
            await stderr.writeLine("Missing cloud credentials to fetch sites.")
            return true
        }
        do {
            let payload = try await client.listSitesPayload(cloudCredentials: cloudCredentials)
            let output = String(data: payload, encoding: .utf8) ?? "<non-utf8>"
            await stdout.writeLine(output)
        } catch {
            await stderr.writeLine("Failed to fetch sites: \(error.localizedDescription)")
        }
        return true
    }

    if listSites {
        guard let cloudCredentials else {
            await stderr.writeLine("Missing cloud credentials to list sites.")
            return true
        }
        do {
            let sites = try await client.listSites(cloudCredentials: cloudCredentials)
            await printSites(sites, stdout: stdout)
        } catch {
            await stderr.writeLine("Failed to fetch sites: \(error.localizedDescription)")
        }
        return true
    }

    return false
}

@discardableResult
private func send(
    command: TydomCommand,
    connection: TydomConnection,
    stderr: ConsoleWriter
) async -> Bool {
    do {
        try await connection.send(text: command.request)
        return true
    } catch {
        await stderr.writeLine("Send failed: \(error)")
        return false
    }
}

private func stdinLines() -> AsyncStream<String> {
    AsyncStream { continuation in
        let task = Task {
            var buffer = Data()
            do {
                for try await byte in FileHandle.standardInput.bytes {
                    if Task.isCancelled { break }
                    if byte == 10 { // \n
                        if let line = String(data: buffer, encoding: .utf8) {
                            continuation.yield(line)
                        }
                        buffer.removeAll(keepingCapacity: true)
                    } else {
                        buffer.append(byte)
                    }
                }
            } catch {
                continuation.finish()
            }
        }

        continuation.onTermination = { _ in
            task.cancel()
        }
    }
}
