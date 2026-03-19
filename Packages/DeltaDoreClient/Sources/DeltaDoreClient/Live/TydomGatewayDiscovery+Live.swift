import Foundation

#if canImport(Network)
import Network
import os

public extension TydomGatewayDiscovery.Dependencies {
    static func live(
        log: @escaping @Sendable (String) -> Void = { _ in }
    ) -> TydomGatewayDiscovery.Dependencies {
        TydomGatewayDiscovery.Dependencies(
            subnetHosts: {
                NetworkProbe.subnetHosts()
            },
            probeHost: { host, port, timeout in
                await NetworkProbe.tcpProbe(host: host, port: port, timeout: timeout)
            },
            probeWebSocketInfo: { host, mac, password, allowInsecureTLS, timeout in
                await WebSocketProbe.probeInfo(
                    host: host,
                    mac: mac,
                    allowInsecureTLS: allowInsecureTLS,
                    timeout: timeout,
                    log: log
                )
            },
            log: log
        )
    }
}

private enum NetworkProbe {
    static func tcpProbe(host: String, port: Int, timeout: TimeInterval) async -> Bool {
        await withCheckedContinuation { continuation in
            guard port > 0, port <= 65535, let portValue = UInt16(exactly: port) else {
                continuation.resume(returning: false)
                return
            }
            let endpoint = NWEndpoint.Host(host)
            let parameters = NWParameters.tcp
            let gate = ContinuationGate()
            guard let nwPort = NWEndpoint.Port(rawValue: portValue) else {
                continuation.resume(returning: false)
                return
            }
            let connection = NWConnection(host: endpoint, port: nwPort, using: parameters)
            let queue = DispatchQueue(label: "tydom.tcp.probe")

            connection.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    connection.cancel()
                    gate.resumeOnce(continuation, value: true)
                case .failed:
                    connection.cancel()
                    gate.resumeOnce(continuation, value: false)
                default:
                    break
                }
            }

            connection.start(queue: queue)
            queue.asyncAfter(deadline: .now() + timeout) {
                connection.cancel()
                gate.resumeOnce(continuation, value: false)
            }
        }
    }

    static func subnetHosts() -> [String] {
        if let network = IPv4Network.inferLocal() {
            return network.hosts
        }
        return []
    }

    private static func ipv4String(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xFF
        let b = (value >> 16) & 0xFF
        let c = (value >> 8) & 0xFF
        let d = value & 0xFF
        return "\(a).\(b).\(c).\(d)"
    }

}

private enum WebSocketProbe {
    static func probeInfo(
        host: String,
        mac: String,
        allowInsecureTLS: Bool,
        timeout: TimeInterval,
        log: @escaping @Sendable (String) -> Void
    ) async -> Bool {
        let normalizedMac = TydomMac.normalize(mac)
        let path = "/mediation/client?mac=\(normalizedMac)&appli=1"
        guard let url = URL(string: "https://\(host):443\(path)") else {
            return false
        }

        let sessionConfig = URLSessionConfiguration.ephemeral
        sessionConfig.timeoutIntervalForRequest = timeout
        sessionConfig.timeoutIntervalForResource = timeout
        let delegate = InsecureTLSDelegate(allowInsecureTLS: allowInsecureTLS, credential: nil)
        let session = URLSession(configuration: sessionConfig, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }

        do {
            _ = try await fetchDigestChallenge(
                using: session,
                url: url,
                host: host,
                includeUpgradeHeaders: true,
                log: log
            )
            log("Discovery validation accepted host=\(host) method=upgrade")
            return true
        } catch {
            log("Discovery validation upgrade failed host=\(host) error=\(error)")
            guard shouldRetryPlainProbe(after: error) else {
                return false
            }
        }

        do {
            _ = try await fetchDigestChallenge(
                using: session,
                url: url,
                host: host,
                includeUpgradeHeaders: false,
                log: log
            )
            log("Discovery validation accepted host=\(host) method=plain")
            return true
        } catch {
            log("Discovery validation plain failed host=\(host) error=\(error)")
            return false
        }
    }

    private static func fetchDigestChallenge(
        using session: URLSession,
        url: URL,
        host: String,
        includeUpgradeHeaders: Bool,
        log: @escaping @Sendable (String) -> Void
    ) async throws -> DigestChallenge {
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        let headers = buildHeaders(host: host, includeUpgradeHeaders: includeUpgradeHeaders)
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw TydomConnection.ConnectionError.invalidResponse
        }

        let status = httpResponse.statusCode
        log("Discovery validation response host=\(host) status=\(status) includeUpgrade=\(includeUpgradeHeaders)")

        let rawHeader = httpResponse.value(forHTTPHeaderField: "WWW-Authenticate")
            ?? httpResponse.allHeaderFields.first { key, _ in
                String(describing: key).lowercased() == "www-authenticate"
            }.flatMap { _, value in
                normalizeHeaderValue(value)
            }
        guard let rawHeader else {
            throw TydomConnection.ConnectionError.missingChallenge
        }
        return try DigestChallenge.parse(from: rawHeader)
    }

    private static func buildHeaders(
        host: String,
        includeUpgradeHeaders: Bool
    ) -> [String: String] {
        var headers: [String: String] = [
            "Host": "\(host):443",
            "Accept": "*/*"
        ]
        guard includeUpgradeHeaders else { return headers }

        headers["Connection"] = "Upgrade"
        headers["Upgrade"] = "websocket"
        headers["Sec-WebSocket-Version"] = "13"
        headers["Sec-WebSocket-Key"] = Data((0..<16).map { UInt8($0) }).base64EncodedString()
        return headers
    }

    private static func normalizeHeaderValue(_ raw: Any) -> String? {
        if let text = raw as? String {
            return text
        }
        if let values = raw as? [String], values.isEmpty == false {
            return values.joined(separator: ", ")
        }
        if let values = raw as? [Any], values.isEmpty == false {
            let joined = values
                .map { String(describing: $0) }
                .joined(separator: ", ")
            return joined.isEmpty ? nil : joined
        }
        let text = String(describing: raw)
        return text.isEmpty ? nil : text
    }

    private static func shouldRetryPlainProbe(after error: Error) -> Bool {
        if let connectionError = error as? TydomConnection.ConnectionError {
            switch connectionError {
            case .missingChallenge, .invalidResponse:
                return true
            default:
                return false
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .networkConnectionLost, .badServerResponse, .cannotParseResponse:
                return true
            default:
                return false
            }
        }
        return false
    }
}

private struct IPv4Network {
    let network: UInt32
    let netmask: UInt32

    static func inferLocal() -> IPv4Network? {
        var addrs: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addrs) == 0, let first = addrs else { return nil }
        defer { freeifaddrs(addrs) }

        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            defer { pointer = current.pointee.ifa_next }
            let flags = current.pointee.ifa_flags
            if (flags & UInt32(IFF_LOOPBACK)) != 0 { continue }
            guard let addr = current.pointee.ifa_addr else { continue }
            guard addr.pointee.sa_family == sa_family_t(AF_INET) else { continue }
            guard let netmask = current.pointee.ifa_netmask else { continue }

            let sockaddr = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let maskaddr = netmask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
            let ip = UInt32(bigEndian: sockaddr.sin_addr.s_addr)
            let mask = UInt32(bigEndian: maskaddr.sin_addr.s_addr)

            if (ip & 0xFFFF0000) == 0xA9FE0000 { continue }

            let network = ip & mask
            return IPv4Network(network: network, netmask: mask)
        }
        return nil
    }

    var hosts: [String] {
        let broadcast = network | ~netmask
        if broadcast <= network {
            return []
        }
        if broadcast - network <= 1 {
            return [IPv4Network.formatIPv4(network)]
        }

        var result: [String] = []
        var ip = network + 1
        while ip < broadcast {
            result.append(IPv4Network.formatIPv4(ip))
            ip += 1
        }
        return result
    }

    private static func formatIPv4(_ value: UInt32) -> String {
        let a = (value >> 24) & 0xff
        let b = (value >> 16) & 0xff
        let c = (value >> 8) & 0xff
        let d = value & 0xff
        return "\(a).\(b).\(c).\(d)"
    }
}

private final class ContinuationGate: Sendable {
    private let didResumeLock = OSAllocatedUnfairLock(initialState: false)

    func resumeOnce<T: Sendable>(_ continuation: CheckedContinuation<T, Never>, value: T) {
        let shouldResume = didResumeLock.withLock { didResume in
            guard !didResume else { return false }
            didResume = true
            return true
        }

        if shouldResume {
            continuation.resume(returning: value)
        }
    }
}

private final class LockedHosts: Sendable {
    private let valuesLock = OSAllocatedUnfairLock(initialState: [String]())

    func append(_ host: String) {
        valuesLock.withLock { values in
            values.append(host)
        }
    }

    func snapshot() -> [String] {
        valuesLock.withLock { values in
            Array(Set(values))
        }
    }
}
#endif
