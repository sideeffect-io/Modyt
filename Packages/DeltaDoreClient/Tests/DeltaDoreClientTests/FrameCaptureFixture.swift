import Foundation
@testable import DeltaDoreClient

struct FrameCaptureFixture {
    struct Frame: Sendable {
        let index: Int
        let uriOrigin: String?
        let transactionId: String?
        let parseError: String?
        let payloadBytes: Int?
        let startLine: String
        let method: String
        let statusCode: Int?
        let headers: [String: String]
        let bodyData: Data?
        let bodyJSON: JSONValue?
        let replayData: Data
    }

    static func loadRedacted() throws -> [Frame] {
        let url = Bundle.module.url(forResource: "frame_types.redacted", withExtension: "txt")
            ?? Bundle.module.url(forResource: "frame_types.redacted", withExtension: "txt", subdirectory: "Fixtures")
        guard let url else {
            throw FixtureError.missingResource
        }
        let text = try String(contentsOf: url, encoding: .utf8)
        return try parseFrames(from: text)
    }

    private static func parseFrames(from text: String) throws -> [Frame] {
        let startMarker = "==================== WEBSOCKET FRAME ====================\n"
        let endMarker = "\n========================================================="

        var frames: [Frame] = []
        var cursor = text.startIndex
        while let startRange = text.range(of: startMarker, range: cursor..<text.endIndex) {
            guard let endRange = text.range(of: endMarker, range: startRange.upperBound..<text.endIndex) else {
                break
            }
            let block = String(text[startRange.upperBound..<endRange.lowerBound])
            if let frame = try parseBlock(block) {
                frames.append(frame)
            }
            cursor = endRange.upperBound
        }

        return frames
    }

    private static func parseBlock(_ block: String) throws -> Frame? {
        let lines = block.components(separatedBy: "\n")
        guard let metadataLineIndex = lines.firstIndex(where: { $0.isEmpty == false }) else { return nil }
        let metadataLine = lines[metadataLineIndex]
        var payloadLines = Array(lines.dropFirst(metadataLineIndex + 1))

        while payloadLines.first?.isEmpty == true {
            payloadLines.removeFirst()
        }
        guard let headerSeparator = payloadLines.firstIndex(where: { $0.isEmpty }) else { return nil }
        let headerLines = Array(payloadLines.prefix(upTo: headerSeparator))
        let bodyLines = Array(payloadLines.dropFirst(headerSeparator + 1))

        let metadataValues = parseMetadataLine(metadataLine)
        let index = metadataValues["index"].flatMap(Int.init) ?? 0
        let uriOrigin = nilIfNA(metadataValues["uriOrigin"])
        let transactionId = nilIfNA(metadataValues["transactionId"])
        let parseError = nilIfNA(metadataValues["parseError"])
        let payloadBytes = metadataValues["payloadBytes"].flatMap(Int.init)

        guard let startLine = headerLines.first else { return nil }
        let method = startLine.split(separator: " ", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        let statusCode: Int? = {
            guard method.hasPrefix("HTTP/") else { return nil }
            let components = startLine.split(separator: " ", omittingEmptySubsequences: true)
            guard components.count >= 2 else { return nil }
            return Int(components[1])
        }()

        var headers: [String: String] = [:]
        for line in headerLines.dropFirst() {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            guard key.isEmpty == false else { continue }
            headers[key] = value
        }

        let replayBodyAndDecoded = makeReplayBodyAndDecodedBody(
            headers: headers,
            bodyLines: bodyLines
        )
        let bodyData = replayBodyAndDecoded.decodedBody

        let bodyJSON: JSONValue? = {
            guard let bodyData, bodyData.isEmpty == false else { return nil }
            return try? JSONDecoder().decode(JSONValue.self, from: bodyData)
        }()

        let replayHeader = headerLines.joined(separator: "\r\n")
        var replayData = Data(replayHeader.utf8)
        replayData.append(contentsOf: [13, 10, 13, 10])
        replayData.append(replayBodyAndDecoded.replayBody)

        return Frame(
            index: index,
            uriOrigin: uriOrigin,
            transactionId: transactionId,
            parseError: parseError,
            payloadBytes: payloadBytes,
            startLine: startLine,
            method: method,
            statusCode: statusCode,
            headers: headers,
            bodyData: bodyData,
            bodyJSON: bodyJSON,
            replayData: replayData
        )
    }

    private static func parseMetadataLine(_ line: String) -> [String: String] {
        var result: [String: String] = [:]
        let chunks = line.components(separatedBy: "|")
        for chunk in chunks {
            let trimmed = chunk.trimmingCharacters(in: .whitespacesAndNewlines)
            guard let separator = trimmed.firstIndex(of: "=") else { continue }
            let key = String(trimmed[..<separator])
            let value = String(trimmed[trimmed.index(after: separator)...])
            result[key] = value
        }
        return result
    }

    private static func nilIfNA(_ value: String?) -> String? {
        guard let value else { return nil }
        return value == "n/a" ? nil : value
    }

    private static func makeReplayBodyAndDecodedBody(
        headers: [String: String],
        bodyLines: [String]
    ) -> (replayBody: Data, decodedBody: Data?) {
        let hasChunkedBody = headers["transfer-encoding"]?.lowercased().contains("chunked") == true
        if hasChunkedBody {
            if let canonical = canonicalizeLFChunkedBody(bodyLines) {
                return canonical
            }
            let fallbackBody = bodyLines.joined(separator: "\r\n")
            return (Data(fallbackBody.utf8), decodeLFChunkedBody(bodyLines))
        }

        let significantLines = trimTrailingEmptyLines(bodyLines)
        let bodyText = significantLines.joined(separator: "\n")
        guard bodyText.isEmpty == false else {
            return (Data(), nil)
        }
        let bodyData = Data(bodyText.utf8)
        return (bodyData, bodyData)
    }

    private static func canonicalizeLFChunkedBody(_ lines: [String]) -> (replayBody: Data, decodedBody: Data?)? {
        var replay = Data()
        var decoded = Data()
        var index = 0

        while index < lines.count {
            let sizeLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 1
            guard sizeLine.isEmpty == false else { continue }
            guard let size = Int(sizeLine, radix: 16) else { return nil }

            replay.append(contentsOf: sizeLine.utf8)
            replay.append(contentsOf: [13, 10])

            if size == 0 {
                replay.append(contentsOf: [13, 10])
                return (replay, decoded)
            }

            var chunkData = Data()
            while index < lines.count, chunkData.count < size {
                chunkData.append(contentsOf: lines[index].utf8)
                index += 1
            }
            guard chunkData.count >= size else { return nil }

            let exactChunk = chunkData.prefix(size)
            replay.append(exactChunk)
            replay.append(contentsOf: [13, 10])
            decoded.append(exactChunk)
        }

        return nil
    }

    private static func decodeLFChunkedBody(_ lines: [String]) -> Data? {
        var output = Data()
        var index = 0

        while index < lines.count {
            let sizeLine = lines[index].trimmingCharacters(in: .whitespacesAndNewlines)
            index += 1
            guard sizeLine.isEmpty == false else { continue }
            guard let size = Int(sizeLine, radix: 16) else { return nil }
            if size == 0 { return output }

            var chunkData = Data()
            while index < lines.count, chunkData.count < size {
                chunkData.append(contentsOf: lines[index].utf8)
                index += 1
            }
            guard chunkData.count >= size else { return nil }
            output.append(chunkData.prefix(size))
        }

        return nil
    }

    private static func trimTrailingEmptyLines(_ lines: [String]) -> [String] {
        var end = lines.count
        while end > 0, lines[end - 1].isEmpty {
            end -= 1
        }
        return Array(lines.prefix(end))
    }
}

enum FixtureError: Error {
    case missingResource
}
