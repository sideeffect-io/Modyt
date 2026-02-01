import Foundation

enum TydomGatewayInfoValidator {
    static func matchesGateway(info: TydomGatewayInfo, expectedMac: String) -> Bool {
        let normalizedExpected = TydomMac.normalize(expectedMac)
        let extracted = extractMac(from: info.payload)
        let normalizedExtracted = extracted.map(TydomMac.normalize)
        DeltaDoreDebugLog.log(
            "Verify gateway info expectedMac=\(normalizedExpected) extractedMac=\(normalizedExtracted ?? "nil") keys=\(Array(info.payload.keys))"
        )
        guard let normalizedExtracted else { return false }
        return normalizedExtracted == normalizedExpected
    }

    private static func extractMac(from payload: [String: JSONValue]) -> String? {
        for (key, value) in payload where key.lowercased().contains("mac") {
            if let mac = findMac(in: value) {
                return mac
            }
        }
        for value in payload.values {
            if let mac = findMac(in: value) {
                return mac
            }
        }
        return nil
    }

    private static func findMac(in value: JSONValue) -> String? {
        switch value {
        case .string(let string):
            let hex = string.filter { $0.isHexDigit }
            guard hex.count == 12 else { return nil }
            return TydomMac.normalize(hex)
        case .object(let dict):
            for (key, value) in dict where key.lowercased().contains("mac") {
                if let mac = findMac(in: value) { return mac }
            }
            for value in dict.values {
                if let mac = findMac(in: value) { return mac }
            }
            return nil
        case .array(let array):
            for value in array {
                if let mac = findMac(in: value) { return mac }
            }
            return nil
        case .number, .bool, .null:
            return nil
        }
    }
}
