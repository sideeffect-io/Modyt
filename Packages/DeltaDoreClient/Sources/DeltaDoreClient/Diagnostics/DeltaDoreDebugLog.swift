import Foundation
import OSLog

enum DeltaDoreDebugLog {
    private static let logger = Logger(
        subsystem: "io.sideeffect.deltadoreclient",
        category: "Diagnostics"
    )

    static func log(_ message: @autoclosure () -> String) {
#if DEBUG
        let text = message()
        if shouldSuppress(text) {
            return
        }
        logger.debug("\(text, privacy: .public)")
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
