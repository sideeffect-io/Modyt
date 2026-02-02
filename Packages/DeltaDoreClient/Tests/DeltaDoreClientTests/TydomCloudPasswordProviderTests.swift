import Foundation
import Testing

@testable import DeltaDoreClient

@Test func cloudPasswordProvider_fetchAccessTokenUsesTokenEndpointAndFormData() async throws {
    let authURL = URL(string: TydomCloudPasswordProvider.Constants.authURL)!
    let tokenURL = URL(string: "https://example.com/token")!
    let recorder = RequestRecorder()

    let session = makeSession { request in
        guard let url = request.url else {
            return (httpResponse(url: authURL, status: 400), Data())
        }
        if url == authURL {
            let payload = #"{"token_endpoint":"\#(tokenURL.absoluteString)"}"#
            return (httpResponse(url: authURL), Data(payload.utf8))
        }
        if url == tokenURL {
            recorder.append(request)
            let payload = #"{"access_token":"token-123"}"#
            return (httpResponse(url: tokenURL), Data(payload.utf8))
        }
        return (httpResponse(url: url, status: 404), Data())
    }

    // When
    let token = try await TydomCloudPasswordProvider.fetchAccessToken(
        email: "user@example.com",
        password: "secret",
        session: session
    )

    // Then
    #expect(token == "token-123")
    let requests = recorder.all()
    let tokenRequest = requests.first { $0.url == tokenURL }
    #expect(tokenRequest != nil)
    #expect(tokenRequest?.httpMethod == "POST")
    #expect(tokenRequest?.value(forHTTPHeaderField: "Content-Type")?.contains("multipart/form-data") == true)
    let body = readBody(from: tokenRequest)
    let bodyString = String(data: body, encoding: .utf8) ?? ""
    #expect(bodyString.contains("name=\"username\""))
    #expect(bodyString.contains("user@example.com"))
    #expect(bodyString.contains("name=\"password\""))
    #expect(bodyString.contains("secret"))
    #expect(bodyString.contains("name=\"grant_type\""))
    #expect(bodyString.contains(TydomCloudPasswordProvider.Constants.authGrantType))
    #expect(bodyString.contains("name=\"client_id\""))
    #expect(bodyString.contains(TydomCloudPasswordProvider.Constants.authClientId))
    #expect(bodyString.contains("name=\"scope\""))
    #expect(bodyString.contains(TydomCloudPasswordProvider.Constants.authScope))
}

@Test func cloudPasswordProvider_fetchAccessTokenMissingTokenEndpointThrows() async {
    let authURL = URL(string: TydomCloudPasswordProvider.Constants.authURL)!

    let session = makeSession { request in
        guard let url = request.url else {
            return (httpResponse(url: authURL, status: 400), Data())
        }
        if url == authURL {
            let payload = #"{"token_endpoint":""}"#
            return (httpResponse(url: authURL), Data(payload.utf8))
        }
        return (httpResponse(url: url, status: 404), Data())
    }

    // When / Then
    do {
        _ = try await TydomCloudPasswordProvider.fetchAccessToken(
            email: "user@example.com",
            password: "secret",
            session: session
        )
        #expect(Bool(false), "Expected missingTokenEndpoint error")
    } catch {
        guard let providerError = error as? TydomCloudPasswordProvider.ProviderError else {
            #expect(Bool(false), "Expected ProviderError, got \\(error)")
            return
        }
        #expect(providerError == .missingTokenEndpoint)
    }
}

@Test func cloudPasswordProvider_fetchAccessTokenMissingAccessTokenThrows() async {
    let authURL = URL(string: TydomCloudPasswordProvider.Constants.authURL)!
    let tokenURL = URL(string: "https://example.com/token")!

    let session = makeSession { request in
        guard let url = request.url else {
            return (httpResponse(url: authURL, status: 400), Data())
        }
        if url == authURL {
            let payload = #"{"token_endpoint":"\#(tokenURL.absoluteString)"}"#
            return (httpResponse(url: authURL), Data(payload.utf8))
        }
        if url == tokenURL {
            let payload = #"{"access_token":""}"#
            return (httpResponse(url: tokenURL), Data(payload.utf8))
        }
        return (httpResponse(url: url, status: 404), Data())
    }

    // When / Then
    do {
        _ = try await TydomCloudPasswordProvider.fetchAccessToken(
            email: "user@example.com",
            password: "secret",
            session: session
        )
        #expect(Bool(false), "Expected missingAccessToken error")
    } catch {
        guard let providerError = error as? TydomCloudPasswordProvider.ProviderError else {
            #expect(Bool(false), "Expected ProviderError, got \\(error)")
            return
        }
        #expect(providerError == .missingAccessToken)
    }
}

@Test func cloudPasswordProvider_fetchGatewayPasswordReturnsMatchingPassword() async throws {
    let authURL = URL(string: TydomCloudPasswordProvider.Constants.authURL)!
    let tokenURL = URL(string: "https://example.com/token")!
    let expectedPassword = "gateway-secret"
    let mac = "aa:bb:cc:dd:ee:ff"

    let session = makeSession { request in
        guard let url = request.url else {
            return (httpResponse(url: authURL, status: 400), Data())
        }
        if url == authURL {
            let payload = #"{"token_endpoint":"\#(tokenURL.absoluteString)"}"#
            return (httpResponse(url: authURL), Data(payload.utf8))
        }
        if url == tokenURL {
            let payload = #"{"access_token":"token-123"}"#
            return (httpResponse(url: tokenURL), Data(payload.utf8))
        }
        if url.absoluteString.hasPrefix(TydomCloudPasswordProvider.Constants.sitesAPI) {
            let payload = """
            {"sites":[{"gateway":{"mac":"AA:BB:CC:DD:EE:FF","password":"\(expectedPassword)"}}]}
            """
            return (httpResponse(url: url), Data(payload.utf8))
        }
        return (httpResponse(url: url, status: 404), Data())
    }

    // When
    let password = try await TydomCloudPasswordProvider.fetchGatewayPassword(
        email: "user@example.com",
        password: "secret",
        mac: mac,
        session: session
    )

    // Then
    #expect(password == expectedPassword)
}

@Test func cloudPasswordProvider_fetchGatewayPasswordRetriesCandidates() async throws {
    let authURL = URL(string: TydomCloudPasswordProvider.Constants.authURL)!
    let tokenURL = URL(string: "https://example.com/token")!
    let mac = "aa:bb:cc:dd:ee:ff"
    let normalized = "AABBCCDDEEFF"
    let recorder = RequestRecorder()

    let session = makeSession { request in
        guard let url = request.url else {
            return (httpResponse(url: authURL, status: 400), Data())
        }
        if url == authURL {
            let payload = #"{"token_endpoint":"\#(tokenURL.absoluteString)"}"#
            return (httpResponse(url: authURL), Data(payload.utf8))
        }
        if url == tokenURL {
            let payload = #"{"access_token":"token-123"}"#
            return (httpResponse(url: tokenURL), Data(payload.utf8))
        }
        if url.absoluteString.hasPrefix(TydomCloudPasswordProvider.Constants.sitesAPI) {
            recorder.append(request)
            if url.absoluteString.hasSuffix(mac) {
                let payload = """
                {"sites":[{"gateway":{"mac":"11:22:33:44:55:66","password":"nope"}}]}
                """
                return (httpResponse(url: url), Data(payload.utf8))
            }
            if url.absoluteString.hasSuffix(normalized) {
                let payload = """
                {"sites":[{"gateway":{"mac":"AA:BB:CC:DD:EE:FF","password":"expected"}}]}
                """
                return (httpResponse(url: url), Data(payload.utf8))
            }
            return (httpResponse(url: url, status: 404), Data())
        }
        return (httpResponse(url: url, status: 404), Data())
    }

    // When
    let password = try await TydomCloudPasswordProvider.fetchGatewayPassword(
        email: "user@example.com",
        password: "secret",
        mac: mac,
        session: session
    )

    // Then
    #expect(password == "expected")
    let urls = recorder.all().compactMap { $0.url?.absoluteString }
    #expect(urls.contains(TydomCloudPasswordProvider.Constants.sitesAPI + mac))
    #expect(urls.contains(TydomCloudPasswordProvider.Constants.sitesAPI + normalized))
}

private final class TestURLProtocol: URLProtocol {
    typealias Handler = (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handlers: [String: Handler] = [:]

    override class func canInit(with request: URLRequest) -> Bool {
        request.value(forHTTPHeaderField: "X-Test-Token") != nil
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler(for: request) else {
            client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func register(handler: @escaping Handler) -> String {
        let token = UUID().uuidString
        lock.lock()
        handlers[token] = handler
        lock.unlock()
        return token
    }

    private static func handler(for request: URLRequest) -> Handler? {
        guard let token = request.value(forHTTPHeaderField: "X-Test-Token") else { return nil }
        lock.lock()
        let handler = handlers[token]
        lock.unlock()
        return handler
    }
}

private final class RequestRecorder {
    private let lock = NSLock()
    private var requests: [URLRequest] = []

    func append(_ request: URLRequest) {
        lock.lock()
        requests.append(request)
        lock.unlock()
    }

    func all() -> [URLRequest] {
        lock.lock()
        let copy = requests
        lock.unlock()
        return copy
    }
}

private func makeSession(
    handler: @escaping TestURLProtocol.Handler
) -> URLSession {
    let token = TestURLProtocol.register(handler: handler)
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [TestURLProtocol.self]
    configuration.httpAdditionalHeaders = ["X-Test-Token": token]
    return URLSession(configuration: configuration)
}

private func httpResponse(
    url: URL,
    status: Int = 200,
    headers: [String: String] = [:]
) -> HTTPURLResponse {
    HTTPURLResponse(
        url: url,
        statusCode: status,
        httpVersion: nil,
        headerFields: headers
    )!
}

private func readBody(from request: URLRequest?) -> Data {
    guard let request else { return Data() }
    if let body = request.httpBody {
        return body
    }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        if count <= 0 { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return data
}
