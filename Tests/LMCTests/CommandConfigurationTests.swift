#if canImport(Testing)
import ArgumentParser
import CoreLittleManComputer
import Testing
@testable import LMC

@Test
func rootConfigurationDeclaresExpectedSubcommands() {
    let subcommands = LMCCommand.configuration.subcommands
    #expect(subcommands.contains { $0 == AssembleCommand.self })
    #expect(subcommands.contains { $0 == RunCommand.self })
    #expect(subcommands.contains { $0 == ReplCommand.self })
    #expect(subcommands.contains { $0 == DisassembleCommand.self })
    #expect(subcommands.contains { $0 == SnapshotCommand.self })
    #expect(subcommands.contains { $0 == StateCommand.self })
    #expect(subcommands.contains { $0 == ExecCommand.self })
    #expect(subcommands.contains { $0 == BreakpointCommand.self })
    #expect(subcommands.contains { $0 == ExportCommand.self })
    #expect(subcommands.contains { $0 == ImportCommand.self })
    #expect(subcommands.count == 10)
}

@Test
func snapshotCommandOffersLifecycleSubcommands() {
    let subcommands = SnapshotCommand.configuration.subcommands
    #expect(subcommands.contains { $0 == SnapshotCommand.Store.self })
    #expect(subcommands.contains { $0 == SnapshotCommand.List.self })
    #expect(subcommands.contains { $0 == SnapshotCommand.Remove.self })
    #expect(subcommands.count == 3)
}

@Test
func versionBannerReflectsSnapshotSchemas() {
    let banner = LMCVersionReporter.banner
    #expect(banner.contains("ProgramSnapshot v\(ProgramSnapshot.currentVersion)"))
    #expect(banner.contains("ProgramStateSnapshot v\(ProgramStateSnapshot.currentVersion)"))
}

@Test
func versionReporterPrintsMultilineSummary() {
    var lines: [String] = []
    LMCVersionReporter().printVersion { line in lines.append(line) }

    #expect(lines.first == LMCVersionReporter.banner)
    #expect(lines.contains("CoreLittleManComputer snapshot schemas:"))
    #expect(lines.contains("  Program: \(ProgramSnapshot.currentVersion)"))
    #expect(lines.contains("  Program state: \(ProgramStateSnapshot.currentVersion)"))
}

@Test
func globalOptionsDefaultToHomeWorkspace() throws {
    let options = try GlobalOptions.parse([])
    #expect(options.workspace == nil)
    #expect(options.color == .auto)
    #expect(options.verbosity == .info)
    let workspace = options.resolveWorkspaceURL()
    #expect(workspace.path.hasSuffix("/.lmc"))
}

@Test
func plainFlagOverridesColourAndVerbosity() throws {
    let options = try GlobalOptions.parse(["--plain"])
    #expect(options.effectiveColorMode == .never)
    #expect(options.effectiveVerbosity == .quiet)
}

@Test
func workspaceOverrideTakesPrecedence() throws {
    let options = try GlobalOptions.parse(["--workspace", "/tmp/test-lmc"])
    let workspace = options.resolveWorkspaceURL()
    #expect(workspace.path == "/tmp/test-lmc")
}

@Test
func versionFlagIsRecognisedDuringParsing() throws {
    let command = try LMCCommand.parseAsRoot(["--version"])
    guard let root = command as? LMCCommand else {
        Issue.record("Expected LMCCommand instance")
        return
    }
    #expect(root.globalOptions.showVersion)
}
#endif
