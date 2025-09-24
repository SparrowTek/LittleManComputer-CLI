@preconcurrency import ArgumentParser
import Foundation

struct ReplCommand: LMCContextualCommand {
    static let configuration = CommandConfiguration(
        abstract: "Launch an interactive Little Man Computer session"
    )

    @OptionGroup
    var globalOptions: GlobalOptions

    @Option(name: .long, help: "Display the contents of a file before starting the REPL")
    var welcome: String?

    @Option(name: .long, help: "Execute commands from a script file before interactive control")
    var script: String?

    func perform(context: CommandContext) async throws {
        let session = REPLSession(context: context)
        try await session.run(welcome: welcome, script: script)
    }
}
