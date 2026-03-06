import Foundation

@MainActor
protocol StartableStore: AnyObject {
    func start()
}
