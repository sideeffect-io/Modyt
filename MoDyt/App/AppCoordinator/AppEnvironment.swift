import Foundation
import DeltaDoreClient

struct AppEnvironment: Sendable {
    let client: DeltaDoreClient
    let repository: DeviceRepository
    let shutterRepository: ShutterRepository
    let now: @Sendable () -> Date
    let log: @Sendable (String) -> Void

    static func live() -> AppEnvironment {
        let databaseURL = AppDirectories.databaseURL()
        let log: @Sendable (String) -> Void = { message in
            #if DEBUG
            print("[MoDyt] \(message)")
            #endif
        }
        let repository = DeviceRepository(databasePath: databaseURL.path, log: log)
        let shutterRepository = ShutterRepository(
            databasePath: databaseURL.path,
            deviceRepository: repository,
            log: log
        )
        return AppEnvironment(
            client: .live(),
            repository: repository,
            shutterRepository: shutterRepository,
            now: Date.init,
            log: log
        )
    }
}

enum AppDirectories {
    static func databaseURL() -> URL {
        let fileManager = FileManager.default
        let baseURL = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        let directory = baseURL.appendingPathComponent("MoDyt", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        return directory.appendingPathComponent("tydom.sqlite")
    }
}
