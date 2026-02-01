import Foundation
import DeltaDoreClient

func parseArguments(_ args: [String]) -> StartupAction {
    var mode: String = "auto"
    var cloudEmail: String?
    var cloudPassword: String?
    var siteIndex: Int?
    var listSites: Bool = false
    var dumpSitesResponse: Bool = false
    var forceLocal: Bool = false
    var forceRemote: Bool = false
    var localIP: String?
    var localMAC: String?
    var clearStorage: Bool = false

    var index = 0
    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--help", "-h":
            return .help(helpText())
        case "--mode":
            index += 1
            guard index < args.count else { return .failure("Missing value for --mode.") }
            mode = args[index].lowercased()
        case "--cloud-email":
            index += 1
            guard index < args.count else { return .failure("Missing value for --cloud-email.") }
            cloudEmail = args[index]
        case "--cloud-password":
            index += 1
            guard index < args.count else { return .failure("Missing value for --cloud-password.") }
            cloudPassword = args[index]
        case "--site-index":
            index += 1
            guard index < args.count, let value = Int(args[index]) else {
                return .failure("Invalid value for --site-index.")
            }
            siteIndex = value
        case "--list-sites":
            listSites = true
        case "--dump-sites-response":
            dumpSitesResponse = true
        case "--force-local":
            forceLocal = true
        case "--force-remote":
            forceRemote = true
        case "--local-ip":
            index += 1
            guard index < args.count else { return .failure("Missing value for --local-ip.") }
            localIP = args[index]
        case "--local-mac":
            index += 1
            guard index < args.count else { return .failure("Missing value for --local-mac.") }
            localMAC = args[index]
        case "--clear-storage":
            clearStorage = true
        default:
            return .failure("Unknown argument: \(arg)")
        }
        index += 1
    }

    let credentials: TydomConnection.CloudCredentials?
    if let cloudEmail, let cloudPassword {
        credentials = TydomConnection.CloudCredentials(email: cloudEmail, password: cloudPassword)
    } else {
        credentials = nil
    }

    switch mode {
    case "auto":
        let options = AutoOptions(
            cloudCredentials: credentials,
            siteIndex: siteIndex,
            forceLocal: forceLocal,
            forceRemote: forceRemote,
            localIP: localIP,
            localMAC: localMAC,
            listSites: listSites,
            dumpSitesResponse: dumpSitesResponse,
            clearStorage: clearStorage
        )
        return .runAuto(options)
    case "stored":
        let options = StoredOptions(
            forceLocal: forceLocal,
            forceRemote: forceRemote,
            clearStorage: clearStorage
        )
        return .runStored(options)
    case "new":
        let options = NewOptions(
            cloudCredentials: credentials,
            siteIndex: siteIndex,
            forceLocal: forceLocal,
            forceRemote: forceRemote,
            localIP: localIP,
            localMAC: localMAC,
            listSites: listSites,
            dumpSitesResponse: dumpSitesResponse,
            clearStorage: clearStorage
        )
        return .runNew(options)
    default:
        return .failure("Invalid --mode value. Use auto, stored, or new.")
    }
}

func helpText() -> String {
    var lines: [String] = []
    lines.append("DeltaDoreCLI")
    lines.append("")
    lines.append("Usage:")
    lines.append("  DeltaDoreCLI --mode auto --cloud-email <email> --cloud-password <password> [--site-index <n>]")
    lines.append("  DeltaDoreCLI --mode stored")
    lines.append("  DeltaDoreCLI --mode new --cloud-email <email> --cloud-password <password> [--site-index <n>]")
    lines.append("")
    lines.append("Options:")
    lines.append("  --mode auto|stored|new       Connection flow (default: auto)")
    lines.append("  --cloud-email <email>        Cloud account email")
    lines.append("  --cloud-password <password>  Cloud account password")
    lines.append("  --site-index <n>             Site index (skips prompt)")
    lines.append("  --list-sites                 List available sites and exit (requires cloud login)")
    lines.append("  --dump-sites-response        Print raw site list response and exit")
    lines.append("  --force-local                Force local mode (stored/new flows)")
    lines.append("  --force-remote               Force remote mode (stored/new flows)")
    lines.append("  --local-ip <ip>              Local gateway IP (required with --force-local for new flow)")
    lines.append("  --local-mac <mac>            Local gateway MAC (required with --force-local for new flow)")
    lines.append("  --clear-storage              Clear stored data before running")
    lines.append("  --help                       Show this help")
    lines.append("")
    lines.append("Once connected, type `help` to list interactive commands.")
    return lines.joined(separator: "\n")
}
