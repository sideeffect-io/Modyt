import Foundation

protocol DomainUpsert: Sendable {
    associatedtype ID: Sendable, Hashable

    var id: ID { get }
}
