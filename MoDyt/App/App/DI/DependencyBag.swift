import Foundation
import DeltaDoreClient

struct DependencyBag: Sendable {
    let localStorageDatasources: LocalStorageDatasources
    let gatewayClient: DeltaDoreClient
    var client: DeltaDoreClient { gatewayClient }

    static let production: DependencyBag = .live()

    static func live(
        databasePath: String = databaseURL.path,
        now: @escaping @Sendable () -> Date = Date.init,
        log: @escaping @Sendable (String) -> Void = { print($0) }
    ) -> DependencyBag {
        let localStorageDatasources = makeLocalStorageDatasources(
            databasePath: databasePath,
            now: now,
            log: log
        )
        let gatewayClient = DeltaDoreClient.live(now: now)
        return DependencyBag(
            localStorageDatasources: localStorageDatasources,
            gatewayClient: gatewayClient
        )
    }
}

let databaseURL: URL = {
    let fileManager = FileManager.default
    let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        ?? fileManager.temporaryDirectory
    let directory = baseURL.appendingPathComponent("MoDyt", isDirectory: true)
    if !fileManager.fileExists(atPath: directory.path) {
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    return directory.appendingPathComponent("tydom.sqlite.v2")
}()
