import Foundation
import DeltaDoreClient

func runCLI(
    connection: TydomConnection,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    rawWebSocketOutput: Bool,
    disablePingPolling: Bool
) async {
    await connection.setKeepAliveEnabled(!disablePingPolling)
    await connection.setAppActive(true)
    let input = CLIInputReader(stream: stdinLines())
    let gatewayCatalog = CLIGatewayCatalog()
    let transactionIdGenerator = CLITransactionIDGenerator()
    let frameLogger = CLIWebSocketFrameLogger.createDefault()
    if let frameLogger {
        await stdout.writeLine("WebSocket frame log file: \(frameLogger.filePath)")
    } else {
        await stderr.writeLine("Unable to create WebSocket frame log file.")
    }

    if !disablePingPolling {
        let initialPingOk = await send(
            command: .ping(),
            connection: connection,
            stdout: stdout,
            stderr: stderr,
            transactionIdGenerator: transactionIdGenerator,
            frameLogger: frameLogger
        )
        guard initialPingOk else {
            await stderr.writeLine("Connection closed before initial ping.")
            await connection.disconnect()
            return
        }
    }

    let messageTask = Task {
        if rawWebSocketOutput {
            let stream = await connection.rawMessages()
            for await payload in stream {
                if let frameLogger {
                    await frameLogger.log(rawPayload: payload)
                }
                await stdout.write(rawFrameText(from: payload))
            }
            return
        }

        let stream = await connection.decodedMessages(
            logger: { message in
                Task { await stderr.writeLine("[polling] \(message)") }
            },
            rawFrameHandler: { raw in
                guard let frameLogger else {
                    return
                }
                Task {
                    await frameLogger.log(rawMessage: raw)
                }
            }
        )
        for await message in stream {
            await gatewayCatalog.ingest(message)
            let knownDevices = await gatewayCatalog.snapshot().devices
            let lines = renderStandardOutputLines(message: message, knownDevices: knownDevices)
            if lines.isEmpty {
                continue
            }
            for line in lines {
                await stdout.writeLine(line)
            }
        }
    }

    await stdout.writeLine("Connected. Pre-loading devices/groups/scenes...")
    await preloadWizardCatalog(
        connection: connection,
        stdout: stdout,
        stderr: stderr,
        catalog: gatewayCatalog,
        transactionIdGenerator: transactionIdGenerator,
        frameLogger: frameLogger
    )

    await stdout.writeLine("Starting wizard mode (`cancel` to return to the command prompt).")
    await runWizard(
        connection: connection,
        stdout: stdout,
        stderr: stderr,
        input: input,
        catalog: gatewayCatalog,
        transactionIdGenerator: transactionIdGenerator,
        frameLogger: frameLogger
    )
    await stdout.writeLine("Type `help` for commands or `wizard` to re-enter guided mode.")

    inputLoop: while let line = await input.nextLine() {
        guard let result = parseInputCommand(line) else { continue }
        switch result {
        case .failure(let error):
            await stderr.writeLine(error.message)
        case .success(let command):
            switch command {
            case .help:
                await stdout.writeLine(commandHelpText())
            case .wizard:
                await runWizard(
                    connection: connection,
                    stdout: stdout,
                    stderr: stderr,
                    input: input,
                    catalog: gatewayCatalog,
                    transactionIdGenerator: transactionIdGenerator,
                    frameLogger: frameLogger
                )
            case .quit:
                break inputLoop
            case .setActive(let isActive):
                await connection.setAppActive(isActive)
                await stdout.writeLine("App active set to \(isActive).")
            case .send(let command):
                await send(
                    command: command,
                    connection: connection,
                    stdout: stdout,
                    stderr: stderr,
                    transactionIdGenerator: transactionIdGenerator,
                    frameLogger: frameLogger
                )
            case .sendMany(let commands):
                for command in commands {
                    await send(
                        command: command,
                        connection: connection,
                        stdout: stdout,
                        stderr: stderr,
                        transactionIdGenerator: transactionIdGenerator,
                        frameLogger: frameLogger
                    )
                }
            case .sendRaw(let raw):
                await send(
                    rawRequest: raw,
                    connection: connection,
                    stdout: stdout,
                    stderr: stderr,
                    transactionIdGenerator: transactionIdGenerator,
                    frameLogger: frameLogger
                )
            }
        }
    }

    await connection.disconnect()
    messageTask.cancel()
    await stdout.writeLine("Disconnected.")
}

private func rawFrameText(from payload: Data) -> String {
    if let text = String(data: payload, encoding: .utf8) {
        return text.hasSuffix("\n") ? text : text + "\n"
    }
    if let text = String(data: payload, encoding: .isoLatin1) {
        return text.hasSuffix("\n") ? text : text + "\n"
    }
    return payload.base64EncodedString() + "\n"
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
func send(
    command: TydomCommand,
    connection: TydomConnection,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    transactionIdGenerator: CLITransactionIDGenerator,
    frameLogger: CLIWebSocketFrameLogger? = nil
) async -> Bool {
    let prepared = await prepareRequestForSend(
        command.request,
        transactionIdGenerator: transactionIdGenerator
    )
    return await sendPreparedRequest(
        prepared,
        connection: connection,
        stdout: stdout,
        stderr: stderr,
        frameLogger: frameLogger
    )
}

@discardableResult
func send(
    rawRequest: String,
    connection: TydomConnection,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    transactionIdGenerator: CLITransactionIDGenerator,
    frameLogger: CLIWebSocketFrameLogger? = nil
) async -> Bool {
    let prepared = await prepareRequestForSend(
        rawRequest,
        transactionIdGenerator: transactionIdGenerator
    )
    return await sendPreparedRequest(
        prepared,
        connection: connection,
        stdout: stdout,
        stderr: stderr,
        frameLogger: frameLogger
    )
}

struct CLIPreparedRequest: Sendable {
    let request: String
    let transactionId: String
    let requestLine: String
}

func prepareRequestForSend(
    _ request: String,
    transactionIdGenerator: CLITransactionIDGenerator
) async -> CLIPreparedRequest {
    let transactionId = await transactionIdGenerator.next()
    let requestWithTransactionID = replacingTransactionID(
        in: request,
        transactionId: transactionId
    )
    let requestLine = requestStartLine(in: requestWithTransactionID)
    return CLIPreparedRequest(
        request: requestWithTransactionID,
        transactionId: transactionId,
        requestLine: requestLine
    )
}

@discardableResult
func sendPreparedRequest(
    _ request: CLIPreparedRequest,
    connection: TydomConnection,
    stdout: ConsoleWriter,
    stderr: ConsoleWriter,
    frameLogger: CLIWebSocketFrameLogger? = nil
) async -> Bool {
    do {
        try await connection.send(text: request.request)
        if let frameLogger {
            await frameLogger.logSentCommand(request)
        }
        if let path = requestPath(fromStartLine: request.requestLine),
           shouldSuppressStandardOutputPath(path) == false {
            await stdout.writeLine("--->>> command sent: tx=\(request.transactionId) | \(request.requestLine)")
        }
        return true
    } catch {
        await stderr.writeLine("Send failed [tx=\(request.transactionId)]: \(error)")
        return false
    }
}

private func requestPath(fromStartLine startLine: String) -> String? {
    let parts = startLine.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count >= 2 else {
        return nil
    }
    return String(parts[1])
}

private func requestStartLine(in request: String) -> String {
    if let line = request.components(separatedBy: "\r\n").first, line.isEmpty == false {
        return line
    }
    if let line = request.components(separatedBy: "\n").first, line.isEmpty == false {
        return line
    }
    return "<invalid request>"
}

private func replacingTransactionID(
    in request: String,
    transactionId: String
) -> String {
    if let range = request.range(of: "\r\n\r\n") {
        let header = String(request[..<range.lowerBound])
        let body = String(request[range.upperBound...])
        let updatedHeader = updatingHeaderLines(
            header,
            lineSeparator: "\r\n",
            transactionId: transactionId
        )
        return updatedHeader + "\r\n\r\n" + body
    }

    if let range = request.range(of: "\n\n") {
        let header = String(request[..<range.lowerBound])
        let body = String(request[range.upperBound...])
        let updatedHeader = updatingHeaderLines(
            header,
            lineSeparator: "\n",
            transactionId: transactionId
        )
        return updatedHeader + "\n\n" + body
    }

    return request
}

private func updatingHeaderLines(
    _ header: String,
    lineSeparator: String,
    transactionId: String
) -> String {
    var lines = header.components(separatedBy: lineSeparator)
    guard lines.isEmpty == false else {
        return header
    }

    var didReplace = false
    for index in lines.indices.dropFirst() {
        if lines[index].lowercased().hasPrefix("transac-id:") {
            lines[index] = "Transac-Id: \(transactionId)"
            didReplace = true
        }
    }

    if didReplace == false {
        lines.append("Transac-Id: \(transactionId)")
    }

    return lines.joined(separator: lineSeparator)
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
