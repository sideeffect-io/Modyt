import Foundation

final class InsecureTLSDelegate: NSObject, URLSessionDelegate, URLSessionTaskDelegate, URLSessionWebSocketDelegate {
    private let allowInsecureTLS: Bool
    private let credential: URLCredential?
    private let onWebSocketOpen: (@Sendable (URLSessionWebSocketTask) -> Void)?
    private let onWebSocketClose: (@Sendable (URLSessionWebSocketTask, URLSessionWebSocketTask.CloseCode, Data?) -> Void)?
    private let onWebSocketComplete: (@Sendable (URLSessionTask, Error?) -> Void)?

    init(
        allowInsecureTLS: Bool,
        credential: URLCredential? = nil,
        onWebSocketOpen: (@Sendable (URLSessionWebSocketTask) -> Void)? = nil,
        onWebSocketClose: (@Sendable (URLSessionWebSocketTask, URLSessionWebSocketTask.CloseCode, Data?) -> Void)? = nil,
        onWebSocketComplete: (@Sendable (URLSessionTask, Error?) -> Void)? = nil
    ) {
        self.allowInsecureTLS = allowInsecureTLS
        self.credential = credential
        self.onWebSocketOpen = onWebSocketOpen
        self.onWebSocketClose = onWebSocketClose
        self.onWebSocketComplete = onWebSocketComplete
    }

    func urlSession(
        _ session: URLSession,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        guard allowInsecureTLS,
              challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
              let trust = challenge.protectionSpace.serverTrust else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, URLCredential(trust: trust))
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didReceive challenge: URLAuthenticationChallenge,
        completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void
    ) {
        let method = challenge.protectionSpace.authenticationMethod
        guard method == NSURLAuthenticationMethodHTTPDigest,
              let credential else {
            completionHandler(.performDefaultHandling, nil)
            return
        }
        completionHandler(.useCredential, credential)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didOpenWithProtocol protocol: String?
    ) {
        let negotiatedProtocol = `protocol` ?? "nil"
        let status = (webSocketTask.response as? HTTPURLResponse)?.statusCode
        let headers = (webSocketTask.response as? HTTPURLResponse)?.allHeaderFields ?? [:]
        DeltaDoreDebugLog.log("WebSocket didOpen protocol=\(negotiatedProtocol) status=\(status.map(String.init) ?? "nil") headers=\(headers)")
        onWebSocketOpen?(webSocketTask)
    }

    func urlSession(
        _ session: URLSession,
        webSocketTask: URLSessionWebSocketTask,
        didCloseWith closeCode: URLSessionWebSocketTask.CloseCode,
        reason: Data?
    ) {
        let reasonString = reason.flatMap { String(data: $0, encoding: .utf8) } ?? "n/a"
        DeltaDoreDebugLog.log("WebSocket didClose code=\(closeCode.rawValue) reason=\(reasonString)")
        onWebSocketClose?(webSocketTask, closeCode, reason)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, task is URLSessionWebSocketTask else { return }
        let status = (task.response as? HTTPURLResponse)?.statusCode
        let headers = (task.response as? HTTPURLResponse)?.allHeaderFields ?? [:]
        DeltaDoreDebugLog.log("WebSocket task completed error=\(error) status=\(status.map(String.init) ?? "nil") headers=\(headers)")
        onWebSocketComplete?(task, error)
    }
}
