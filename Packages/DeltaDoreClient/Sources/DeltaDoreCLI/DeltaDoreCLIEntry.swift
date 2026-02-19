import Foundation
import DeltaDoreClient

@main
struct DeltaDoreCLI {
    static func main() async {
        let stdout = ConsoleWriter(handle: .standardOutput)
        let stderr = ConsoleWriter(handle: .standardError)

        let action = parseArguments(Array(CommandLine.arguments.dropFirst()))
        switch action {
        case .help(let text):
            await stdout.writeLine(text)
            return
        case .failure(let message):
            await stderr.writeLine(message)
            await stdout.writeLine(helpText())
            return
        case .runAuto(let options):
            guard let connection = await connectAuto(
                options: options,
                stdout: stdout,
                stderr: stderr
            ) else {
                return
            }
            await runCLI(
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                rawWebSocketOutput: options.rawWebSocketOutput,
                disablePingPolling: options.disablePingPolling
            )
        case .runStored(let options):
            guard let connection = await connectStored(
                options: options,
                stdout: stdout,
                stderr: stderr
            ) else {
                return
            }
            await runCLI(
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                rawWebSocketOutput: options.rawWebSocketOutput,
                disablePingPolling: options.disablePingPolling
            )
        case .runNew(let options):
            guard let connection = await connectNew(
                options: options,
                stdout: stdout,
                stderr: stderr
            ) else {
                return
            }
            await runCLI(
                connection: connection,
                stdout: stdout,
                stderr: stderr,
                rawWebSocketOutput: options.rawWebSocketOutput,
                disablePingPolling: options.disablePingPolling
            )
        }
    }
}
