import Foundation
import DeltaDoreClient

enum StartupAction: Sendable {
    case runAuto(AutoOptions)
    case runStored(StoredOptions)
    case runNew(NewOptions)
    case help(String)
    case failure(String)
}

struct AutoOptions: Sendable {
    let cloudCredentials: TydomConnection.CloudCredentials?
    let siteIndex: Int?
    let forceLocal: Bool
    let forceRemote: Bool
    let localIP: String?
    let localMAC: String?
    let listSites: Bool
    let dumpSitesResponse: Bool
    let clearStorage: Bool
}

struct StoredOptions: Sendable {
    let forceLocal: Bool
    let forceRemote: Bool
    let clearStorage: Bool
}

struct NewOptions: Sendable {
    let cloudCredentials: TydomConnection.CloudCredentials?
    let siteIndex: Int?
    let forceLocal: Bool
    let forceRemote: Bool
    let localIP: String?
    let localMAC: String?
    let listSites: Bool
    let dumpSitesResponse: Bool
    let clearStorage: Bool
}

enum CLICommand: Sendable {
    case help
    case quit
    case setActive(Bool)
    case send(TydomCommand)
    case sendMany([TydomCommand])
    case sendRaw(String)
}

struct CLIParseError: Error, Sendable {
    let message: String
}

actor ConsoleWriter {
    private let handle: FileHandle

    init(handle: FileHandle) {
        self.handle = handle
    }

    func writeLine(_ line: String) {
        write(line + "\n")
    }

    func write(_ text: String) {
        guard let data = text.data(using: .utf8) else { return }
        handle.write(data)
    }
}
