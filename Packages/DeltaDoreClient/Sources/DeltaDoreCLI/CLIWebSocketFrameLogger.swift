import Foundation
import DeltaDoreClient

actor CLIWebSocketFrameLogger {
    nonisolated let filePath: String
    private let handle: FileHandle
    private var frameCount: Int = 0
    private let timestampFormatter: ISO8601DateFormatter

    init(fileURL: URL, handle: FileHandle) {
        self.filePath = fileURL.path
        self.handle = handle
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        self.timestampFormatter = formatter
    }

    deinit {
        try? handle.close()
    }

    static func createDefault(fileManager: FileManager = .default) -> CLIWebSocketFrameLogger? {
        let logsDirectory = fileManager.homeDirectoryForCurrentUser
            .appendingPathComponent(".deltadorecli", isDirectory: true)
            .appendingPathComponent("logs", isDirectory: true)

        do {
            try fileManager.createDirectory(at: logsDirectory, withIntermediateDirectories: true)
        } catch {
            return nil
        }

        let filename = "websocket-frames.log"
        let fileURL = logsDirectory.appendingPathComponent(filename, isDirectory: false)

        if fileManager.fileExists(atPath: fileURL.path) {
            do {
                try fileManager.removeItem(at: fileURL)
            } catch {
                return nil
            }
        }

        let created = fileManager.createFile(atPath: fileURL.path, contents: nil)
        if created == false {
            return nil
        }

        guard let handle = try? FileHandle(forWritingTo: fileURL) else {
            return nil
        }

        return CLIWebSocketFrameLogger(fileURL: fileURL, handle: handle)
    }

    func log(rawMessage: TydomRawMessage) {
        if isPingMessage(rawMessage) {
            return
        }

        frameCount += 1
        let timestamp = timestampFormatter.string(from: Date())
        let metadata = [
            "index=\(frameCount)",
            "timestamp=\(timestamp)",
            "uriOrigin=\(rawMessage.uriOrigin ?? "n/a")",
            "transactionId=\(rawMessage.transactionId ?? "n/a")",
            "parseError=\(rawMessage.parseError ?? "n/a")",
            "payloadBytes=\(rawMessage.payload.count)"
        ].joined(separator: " | ")
        let payloadText = readableString(from: rawMessage.payload)
        writeDelimitedEntry(
            title: "WEBSOCKET FRAME",
            text: metadata + "\n" + payloadText
        )
    }

    func logSentCommand(_ request: CLIPreparedRequest) {
        if requestPath(fromStartLine: request.requestLine) == "/ping" {
            return
        }

        frameCount += 1
        let timestamp = timestampFormatter.string(from: Date())
        let parsed = parseRequestText(request.request)

        let entry: [String: Any] = [
            "index": frameCount,
            "timestamp": timestamp,
            "entryType": "outboundCommand",
            "transactionId": request.transactionId,
            "requestLine": request.requestLine,
            "headers": parsed.headers,
            "body": parsed.body
        ]

        writeDelimitedEntry(title: "SENT COMMAND", object: entry)
    }

    func log(rawPayload: Data) {
        if isPingPayload(rawPayload) {
            return
        }

        frameCount += 1
        let timestamp = timestampFormatter.string(from: Date())
        let metadata = [
            "index=\(frameCount)",
            "timestamp=\(timestamp)",
            "frameType=rawPayload",
            "payloadBytes=\(rawPayload.count)"
        ].joined(separator: " | ")
        let payloadText = readableString(from: rawPayload)
        writeDelimitedEntry(
            title: "WEBSOCKET FRAME",
            text: metadata + "\n" + payloadText
        )
    }

    private func writeDelimitedEntry(title: String, object: [String: Any]) {
        let delimiter = "\n==================== \(title) ====================\n"
        let jsonText = prettyJSONString(from: object) ?? "\(object)"
        let suffix = "\n=========================================================\n"
        write(delimiter + jsonText + suffix)
    }

    private func writeDelimitedEntry(title: String, text: String) {
        let delimiter = "\n==================== \(title) ====================\n"
        let suffix = "\n=========================================================\n"
        write(delimiter + text + suffix)
    }

    private func write(_ text: String) {
        guard let data = text.data(using: .utf8) else {
            return
        }
        handle.write(data)
    }

    private func prettyJSONString(from object: [String: Any]) -> String? {
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys]),
              let text = String(data: data, encoding: .utf8) else {
            return nil
        }
        return text
    }

    private func jsonOrText(from data: Data?) -> Any {
        guard let data, data.isEmpty == false else {
            return NSNull()
        }
        if let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }
        return readableString(from: data)
    }

    private func parseRequestText(_ request: String) -> (headers: [String: String], body: Any) {
        if let range = request.range(of: "\r\n\r\n") {
            let headerPart = String(request[..<range.lowerBound])
            let bodyPart = String(request[range.upperBound...])
            return (
                headers: parseHeaderLines(headerPart),
                body: jsonOrText(from: bodyPart)
            )
        }

        if let range = request.range(of: "\n\n") {
            let headerPart = String(request[..<range.lowerBound])
            let bodyPart = String(request[range.upperBound...])
            return (
                headers: parseHeaderLines(headerPart),
                body: jsonOrText(from: bodyPart)
            )
        }

        return (headers: [:], body: NSNull())
    }

    private func parseHeaderLines(_ headerText: String) -> [String: String] {
        let normalized = headerText.replacingOccurrences(of: "\r\n", with: "\n")
        let lines = normalized.components(separatedBy: "\n")
        guard lines.isEmpty == false else {
            return [:]
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let colonIndex = line.firstIndex(of: ":") else {
                continue
            }
            let key = line[..<colonIndex].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else {
                continue
            }
            headers[key] = value
        }
        return headers
    }

    private func jsonOrText(from text: String) -> Any {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.isEmpty == false else {
            return NSNull()
        }
        if let data = trimmed.data(using: .utf8),
           let json = try? JSONSerialization.jsonObject(with: data) {
            return json
        }
        return trimmed
    }

    private func readableString(from data: Data) -> String {
        if let utf8 = String(data: data, encoding: .utf8) {
            return utf8
        }
        if let latin1 = String(data: data, encoding: .isoLatin1) {
            return latin1
        }
        return data.base64EncodedString()
    }

    private func requestPath(fromStartLine startLine: String) -> String? {
        let parts = startLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count >= 2 else {
            return nil
        }
        return String(parts[1])
    }

    private func isPingMessage(_ rawMessage: TydomRawMessage) -> Bool {
        if rawMessage.uriOrigin == "/ping" {
            return true
        }

        guard let frame = rawMessage.frame else {
            return false
        }

        switch frame {
        case .request(let request):
            return request.path == "/ping"
        case .response(let response):
            return response.headerValue("uri-origin") == "/ping"
        }
    }

    private func isPingPayload(_ payload: Data) -> Bool {
        let text = String(data: payload, encoding: .isoLatin1)
            ?? String(decoding: payload, as: UTF8.self)
        let lowered = text.lowercased()
        return lowered.contains("get /ping ")
            || lowered.contains("uri-origin: /ping")
    }
}
