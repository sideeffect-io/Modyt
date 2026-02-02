import CryptoKit
import Foundation
import Testing

@testable import DeltaDoreClient

@Test func digestChallenge_parsesValidHeader() throws {
    // Given
    let header = "Digest realm=\"test-realm\", nonce=\"abc123\", qop=\"auth\", opaque=\"xyz\", algorithm=\"MD5\""

    // When
    let challenge = try DigestChallenge.parse(from: header)

    // Then
    #expect(challenge.realm == "test-realm")
    #expect(challenge.nonce == "abc123")
    #expect(challenge.qop == "auth")
    #expect(challenge.opaque == "xyz")
    #expect(challenge.algorithm == "MD5")
}

@Test func digestChallenge_rejectsMissingPrefix() {
    // Given
    let header = "Basic realm=\"test-realm\", nonce=\"abc123\""

    // When / Then
    do {
        _ = try DigestChallenge.parse(from: header)
        #expect(Bool(false), "Expected invalidChallenge error")
    } catch {
        guard let error = error as? TydomConnection.ConnectionError else {
            #expect(Bool(false), "Expected ConnectionError, got \\(error)")
            return
        }
        #expect(error == .invalidChallenge)
    }
}

@Test func digestChallenge_requiresRealmAndNonce() {
    // Given
    let header = "Digest nonce=\"abc123\""

    // When / Then
    do {
        _ = try DigestChallenge.parse(from: header)
        #expect(Bool(false), "Expected invalidChallenge error")
    } catch {
        guard let error = error as? TydomConnection.ConnectionError else {
            #expect(Bool(false), "Expected ConnectionError, got \\(error)")
            return
        }
        #expect(error == .invalidChallenge)
    }
}

@Test func digestAuthorizationBuilder_buildsWithQop() throws {
    // Given
    let challenge = DigestChallenge(
        realm: "test-realm",
        nonce: "abc123",
        qop: "auth,auth-int",
        opaque: "xyz",
        algorithm: "MD5"
    )
    let username = "user"
    let password = "pass"
    let method = "GET"
    let uri = "/devices"
    let cnonce = deterministicRandomBytes(16).hexString
    let ha1 = md5Hex("\(username):\(challenge.realm):\(password)")
    let ha2 = md5Hex("\(method):\(uri)")
    let response = md5Hex("\(ha1):\(challenge.nonce):00000001:\(cnonce):auth:\(ha2)")
    let expected = "Digest username=\"\(username)\", realm=\"\(challenge.realm)\", nonce=\"\(challenge.nonce)\", uri=\"\(uri)\", response=\"\(response)\", algorithm=MD5, qop=auth, nc=00000001, cnonce=\"\(cnonce)\", opaque=\"\(challenge.opaque!)\""

    // When
    let authorization = try DigestAuthorizationBuilder.build(
        challenge: challenge,
        username: username,
        password: password,
        method: method,
        uri: uri,
        randomBytes: deterministicRandomBytes
    )

    // Then
    #expect(authorization == expected)
}

@Test func digestAuthorizationBuilder_buildsWithoutQop() throws {
    // Given
    let challenge = DigestChallenge(
        realm: "test-realm",
        nonce: "abc123",
        qop: nil,
        opaque: nil,
        algorithm: nil
    )
    let username = "user"
    let password = "pass"
    let method = "GET"
    let uri = "/devices"
    let ha1 = md5Hex("\(username):\(challenge.realm):\(password)")
    let ha2 = md5Hex("\(method):\(uri)")
    let response = md5Hex("\(ha1):\(challenge.nonce):\(ha2)")
    let expected = "Digest username=\"\(username)\", realm=\"\(challenge.realm)\", nonce=\"\(challenge.nonce)\", uri=\"\(uri)\", response=\"\(response)\""

    // When
    let authorization = try DigestAuthorizationBuilder.build(
        challenge: challenge,
        username: username,
        password: password,
        method: method,
        uri: uri,
        randomBytes: deterministicRandomBytes
    )

    // Then
    #expect(authorization == expected)
}

@Test func digestAuthorizationBuilder_rejectsUnsupportedAlgorithm() {
    // Given
    let challenge = DigestChallenge(
        realm: "test-realm",
        nonce: "abc123",
        qop: nil,
        opaque: nil,
        algorithm: "SHA-256"
    )

    // When / Then
    do {
        _ = try DigestAuthorizationBuilder.build(
            challenge: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/devices",
            randomBytes: deterministicRandomBytes
        )
        #expect(Bool(false), "Expected unsupportedAlgorithm error")
    } catch {
        guard let error = error as? TydomConnection.ConnectionError else {
            #expect(Bool(false), "Expected ConnectionError, got \\(error)")
            return
        }
        #expect(error == .unsupportedAlgorithm("SHA-256"))
    }
}

@Test func digestAuthorizationBuilder_rejectsUnsupportedQop() {
    // Given
    let challenge = DigestChallenge(
        realm: "test-realm",
        nonce: "abc123",
        qop: "auth-int",
        opaque: nil,
        algorithm: nil
    )

    // When / Then
    do {
        _ = try DigestAuthorizationBuilder.build(
            challenge: challenge,
            username: "user",
            password: "pass",
            method: "GET",
            uri: "/devices",
            randomBytes: deterministicRandomBytes
        )
        #expect(Bool(false), "Expected unsupportedQop error")
    } catch {
        guard let error = error as? TydomConnection.ConnectionError else {
            #expect(Bool(false), "Expected ConnectionError, got \\(error)")
            return
        }
        #expect(error == .unsupportedQop("auth-int"))
    }
}

private func deterministicRandomBytes(_ count: Int) -> [UInt8] {
    (0..<count).map { UInt8($0 & 0xFF) }
}

private func md5Hex(_ string: String) -> String {
    let digest = Insecure.MD5.hash(data: Data(string.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

private extension Array where Element == UInt8 {
    var hexString: String {
        map { String(format: "%02x", $0) }.joined()
    }
}
