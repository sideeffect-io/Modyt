import Foundation

protocol DomainType: Sendable, Equatable, Codable {
    associatedtype ID: Sendable, Hashable, Codable

    var id: ID { get }
    var name: String { get }
    var isFavorite: Bool { get set }
    var dashboardOrder: Int? { get set }
    var updatedAt: Date { get set }
}
