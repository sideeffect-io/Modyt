import Foundation
import Testing

@testable import DeltaDoreClient

@Test func cloudSitesProvider_fetchSitesPayloadAddsAuthorizationHeader() async throws {
    let recorder = RequestRecorder()
    let payload = #"{"sites":[{"id":"1","name":"Home","gateways":[{"mac":"aa:bb:cc:dd:ee:ff","name":"GW"}]}]}"#
    let session = makeSession { request in
        recorder.append(request)
        return (httpResponse(url: request.url!), Data(payload.utf8))
    }

    // When
    let data = try await TydomCloudSitesProvider.fetchSitesPayload(
        accessToken: "token-123",
        session: session
    )

    // Then
    #expect(String(data: data, encoding: .utf8) == payload)
    let request = recorder.all().first
    #expect(request?.value(forHTTPHeaderField: "Authorization") == "Bearer token-123")
}

@Test func cloudSitesProvider_fetchSitesDecodesStandardPayload() async throws {
    let payload = """
    {"sites":[{"id":"site-1","name":"Home","gateways":[{"mac":"aa:bb:cc:dd:ee:ff","name":"Gateway"}]}]}
    """
    let session = makeSession { request in
        return (httpResponse(url: request.url!), Data(payload.utf8))
    }

    // When
    let sites = try await TydomCloudSitesProvider.fetchSites(
        accessToken: "token-123",
        session: session
    )

    // Then
    #expect(sites.count == 1)
    #expect(sites[0].id == "site-1")
    #expect(sites[0].name == "Home")
    #expect(sites[0].gateways.count == 1)
    #expect(sites[0].gateways[0].mac == "AABBCCDDEEFF")
    #expect(sites[0].gateways[0].name == "Gateway")
}

@Test func cloudSitesProvider_fetchSitesDecodesFallbackPayload() async throws {
    let payload = """
    {
      "data": {
        "site_access_list": [
          {
            "site": {
              "id": "fallback-1",
              "label": "Fallback Site",
              "gateway": {
                "gateway_mac": "aa:bb:cc:dd:ee:ff",
                "label": "Fallback Gateway"
              }
            }
          }
        ]
      }
    }
    """
    let session = makeSession { request in
        return (httpResponse(url: request.url!), Data(payload.utf8))
    }

    // When
    let sites = try await TydomCloudSitesProvider.fetchSites(
        accessToken: "token-123",
        session: session
    )

    // Then
    #expect(sites.count == 1)
    #expect(sites[0].id == "fallback-1")
    #expect(sites[0].name == "Fallback Site")
    #expect(sites[0].gateways.count == 1)
    #expect(sites[0].gateways[0].mac == "AABBCCDDEEFF")
    #expect(sites[0].gateways[0].name == "Fallback Gateway")
}

@Test func cloudSitesProvider_fetchSitesInvalidPayloadThrows() async {
    let payload = #"{"foo":"bar"}"#
    let session = makeSession { request in
        return (httpResponse(url: request.url!), Data(payload.utf8))
    }

    // When / Then
    do {
        _ = try await TydomCloudSitesProvider.fetchSites(
            accessToken: "token-123",
            session: session
        )
        #expect(Bool(false), "Expected invalidPayload error")
    } catch {
        guard let providerError = error as? TydomCloudSitesProvider.ProviderError else {
            #expect(Bool(false), "Expected ProviderError, got \\(error)")
            return
        }
        switch providerError {
        case .invalidPayload:
            #expect(Bool(true))
        default:
            #expect(Bool(false), "Expected invalidPayload, got \\(providerError)")
        }
    }
}

@Test func cloudSitesProvider_fetchSitesPayloadNon2xxThrows() async {
    let session = makeSession { request in
        return (httpResponse(url: request.url!, status: 500), Data())
    }

    // When / Then
    do {
        _ = try await TydomCloudSitesProvider.fetchSitesPayload(
            accessToken: "token-123",
            session: session
        )
        #expect(Bool(false), "Expected invalidResponse error")
    } catch {
        guard let providerError = error as? TydomCloudSitesProvider.ProviderError else {
            #expect(Bool(false), "Expected ProviderError, got \\(error)")
            return
        }
        switch providerError {
        case .invalidResponse:
            #expect(Bool(true))
        default:
            #expect(Bool(false), "Expected invalidResponse, got \\(providerError)")
        }
    }
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
