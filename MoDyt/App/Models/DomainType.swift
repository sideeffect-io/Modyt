import Foundation

protocol DomainType: Sendable, Equatable, Codable {
    var id: String { get }
    var name: String { get }
    var isFavorite: Bool { get set }
    var dashboardOrder: Int? { get set }
    var updatedAt: Date { get set }
}
