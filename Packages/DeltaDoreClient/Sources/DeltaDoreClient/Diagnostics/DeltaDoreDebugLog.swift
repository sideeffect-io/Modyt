import Foundation

enum DeltaDoreDebugLog {
    static func log(_ message: @autoclosure () -> String) {
#if DEBUG
        print("[DeltaDoreClient] \(message())")
#endif
    }
}
