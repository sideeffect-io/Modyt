import Foundation

enum DeltaDoreDebugLog {
    static func log(_ message: @autoclosure () -> String) {
#if DEBUG
        let text = message()
        if shouldSuppress(text) {
            return
        }
        let line = "[DeltaDoreClient] \(text)\n"
        guard let data = line.data(using: .utf8) else {
            return
        }
        FileHandle.standardError.write(data)
#endif
    }

    private static func shouldSuppress(_ message: String) -> Bool {
        let normalized = message.lowercased()

        // Drop noisy WebSocket frame traffic logs entirely.
        if normalized.contains("websocket send bytes=") {
            return true
        }
        if normalized.contains("websocket recv data bytes=") {
            return true
        }

        // Drop ping-specific diagnostics.
        guard normalized.contains("/ping") else {
            return false
        }
        if normalized.contains("websocket ping ") {
            return true
        }

        return false
    }
}
