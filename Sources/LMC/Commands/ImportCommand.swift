@preconcurrency import ArgumentParser
import CoreLittleManComputer
import Foundation

struct ImportCommand: LMCContextualCommand {
    static let configuration = CommandConfiguration(
        commandName: "import",
        abstract: "Import a Little Man Computer program bundle",
        discussion: """
            Import a program bundle that was exported from another system or user.

            The import process will:
            - Validate the bundle format and version
            - Store the program in your workspace
            - Optionally restore state, assembly, and breakpoints
            - Handle naming conflicts with --force or --rename

            Examples:
              lmc import shared.lmcbundle              Import with original name
              lmc import shared.lmcbundle --as demo    Import with new name
              lmc import shared.lmcbundle --force      Overwrite existing program
              cat bundle.json | lmc import --stdin     Import from stdin
            """
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(
        help: "Path to the export bundle file",
        completion: .file(extensions: ["lmcbundle", "json"])
    )
    var bundle: String?

    @Option(
        name: .long,
        help: "Name to use for the imported program (defaults to original name)"
    )
    var `as`: String?

    @Flag(
        name: .long,
        help: "Read bundle data from stdin instead of a file"
    )
    var stdin: Bool = false

    @Flag(
        name: .long,
        help: "Overwrite existing program with the same name"
    )
    var force: Bool = false

    @Flag(
        name: .long,
        help: "Show bundle metadata without importing"
    )
    var info: Bool = false

    @Flag(
        name: .long,
        help: "Import only the program, ignoring state and breakpoints"
    )
    var programOnly: Bool = false

    func perform(context: CommandContext) async throws {
        let snapshotService = context.services.snapshot

        // Read bundle data
        let bundleData: Data
        if stdin {
            bundleData = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            guard let bundlePath = bundle else {
                throw CLIValidationError("Provide a bundle file path or use --stdin")
            }
            bundleData = try Data(contentsOf: URL(fileURLWithPath: bundlePath))
        }

        // Decode bundle to check metadata
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundleInfo = try decoder.decode(SnapshotService.ExportBundle.self, from: bundleData)

        // Show info if requested
        if info {
            printBundleInfo(bundleInfo)
            return
        }

        // Check for naming conflicts
        let targetName = `as` ?? bundleInfo.metadata.originalName
        if !force {
            do {
                _ = try snapshotService.resolveProgramURL(for: targetName)
                // If we got here, the program exists
                throw CLIValidationError(
                    "Program '\(targetName)' already exists. Use --force to overwrite or --as to rename."
                )
            } catch SnapshotService.Error.notFound {
                // Good, program doesn't exist
            }
        }

        // Prepare import data (potentially stripping state/breakpoints)
        let importData: Data
        if programOnly && (bundleInfo.state != nil || bundleInfo.breakpoints != nil) {
            // Create a modified bundle without state and breakpoints
            var modifiedBundle = bundleInfo
            modifiedBundle = SnapshotService.ExportBundle(
                version: bundleInfo.version,
                metadata: bundleInfo.metadata,
                program: bundleInfo.program,
                state: nil,
                assembly: bundleInfo.assembly,
                breakpoints: nil
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            importData = try encoder.encode(modifiedBundle)
        } else {
            importData = bundleData
        }

        // Perform the import
        let (programURL, stateURL) = try await snapshotService.importProgram(
            from: importData,
            as: targetName
        )

        // Report success
        print("✓ Imported '\(targetName)' successfully")

        // Show what was imported
        var imported: [String] = ["program"]
        if bundleInfo.assembly != nil {
            imported.append("assembly")
        }
        if !programOnly {
            if bundleInfo.state != nil && stateURL != nil {
                imported.append("state")
            }
            if let breakpoints = bundleInfo.breakpoints, !breakpoints.isEmpty {
                imported.append("\(breakpoints.count) breakpoint\(breakpoints.count == 1 ? "" : "s")")
            }
        }
        print("  Components: \(imported.joined(separator: ", "))")

        // Show original metadata
        if let desc = bundleInfo.metadata.description {
            print("  Description: \(desc)")
        }
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        print("  Originally exported: \(dateFormatter.string(from: bundleInfo.metadata.exportedAt))")
    }

    private func printBundleInfo(_ bundle: SnapshotService.ExportBundle) {
        print("Export Bundle Information:")
        print("  Version: \(bundle.version)")
        print("  Original name: \(bundle.metadata.originalName)")

        if let desc = bundle.metadata.description {
            print("  Description: \(desc)")
        }

        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        print("  Exported at: \(dateFormatter.string(from: bundle.metadata.exportedAt))")

        if let exportedBy = bundle.metadata.exportedBy {
            print("  Exported by: \(exportedBy)")
        }

        print("  Platform: \(bundle.metadata.platform)")

        print("\nContents:")
        print("  Program: \(bundle.program.words.count) words")

        if let state = bundle.state {
            print("  State: counter=\(state.counter), accumulator=\(state.accumulator), cycles=\(state.cycles)")
        }

        if bundle.assembly != nil {
            print("  Assembly: included")
        }

        if let breakpoints = bundle.breakpoints {
            print("  Breakpoints: \(breakpoints.map { String(format: "%03d", $0) }.joined(separator: ", "))")
        }
    }
}

private struct CLIValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}