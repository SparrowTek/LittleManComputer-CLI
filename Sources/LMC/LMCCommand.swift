@preconcurrency import ArgumentParser
import CoreLittleManComputer

struct LMCCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "lmc",
        abstract: "Little Man Computer command-line interface",
        discussion: "Assemble programs, execute snapshots, and inspect state using CoreLittleManComputer.",
        version: LMCVersionReporter.banner,
        subcommands: [
            AssembleCommand.self,
            RunCommand.self,
            ReplCommand.self,
            DisassembleCommand.self,
            SnapshotCommand.self,
            StateCommand.self,
            ExecCommand.self,
            BreakpointCommand.self,
            ExportCommand.self,
            ImportCommand.self
        ],
        defaultSubcommand: nil
    )

    @OptionGroup
    var globalOptions: GlobalOptions

    func run() async throws {
        if globalOptions.showVersion {
            LMCVersionReporter().printVersion()
            throw ExitCode.success
        }

        throw CleanExit.helpRequest(Self.self)
    }
}

protocol LMCContextualCommand: AsyncParsableCommand {
    var globalOptions: GlobalOptions { get }
    func perform(context: CommandContext) async throws
}

extension LMCContextualCommand {
    func run() async throws {
        let context = CommandContext(globalOptions: globalOptions)
        try await perform(context: context)
    }

    func unimplemented(_ feature: StaticString) -> CleanExit {
        CleanExit.message("`\(feature)` is not implemented yet. Track progress in plan.md.")
    }
}
