import Foundation
import Testing

@testable import DeltaDoreClient

#if canImport(Security)
@Test func keychainStore_saveLoadDeleteRoundTrip() async throws {
    // Given
    let service = "com.delta.dore.test.\(UUID().uuidString)"
    let account = "account-\(UUID().uuidString)"
    let store = KeychainStore<TestPayload>(service: service)
    let payload = TestPayload(token: "secret", counter: 42)

    // When
    try await store.save(account: account, value: payload)
    let loaded = try await store.load(account: account)
    try await store.delete(account: account)
    let afterDelete = try await store.load(account: account)

    // Then
    #expect(loaded == payload)
    #expect(afterDelete == nil)
}

@Test func keychainStore_saveUpdatesExistingValue() async throws {
    // Given
    let service = "com.delta.dore.test.\(UUID().uuidString)"
    let account = "account-\(UUID().uuidString)"
    let store = KeychainStore<TestPayload>(service: service)

    // When
    try await store.save(account: account, value: TestPayload(token: "first", counter: 1))
    try await store.save(account: account, value: TestPayload(token: "second", counter: 2))
    let loaded = try await store.load(account: account)
    try await store.delete(account: account)

    // Then
    #expect(loaded == TestPayload(token: "second", counter: 2))
}

@Test func keychainStore_deleteMissingAccountDoesNotThrow() async throws {
    // Given
    let service = "com.delta.dore.test.\(UUID().uuidString)"
    let account = "account-\(UUID().uuidString)"
    let store = KeychainStore<TestPayload>(service: service)

    // When / Then
    try await store.delete(account: account)
    #expect(try await store.load(account: account) == nil)
}

private struct TestPayload: Codable, Equatable, Sendable {
    let token: String
    let counter: Int
}
#endif
