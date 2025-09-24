@preconcurrency import ArgumentParser
import CoreLittleManComputer
import Foundation

struct ExportCommand: LMCContextualCommand {
    static let configuration = CommandConfiguration(
        commandName: "export",
        abstract: "Export a Little Man Computer program for sharing",
        discussion: """
            Export a program snapshot as a portable bundle that can be shared
            with others or imported on another system.

            The export bundle includes:
            - The compiled program
            - Optional: Current state (if --state is used)
            - Optional: Assembly source (if available)
            - Optional: Breakpoints (if set)
            - Metadata (export date, platform, etc.)

            Examples:
              lmc export myprogram                        Export just the program
              lmc export myprogram --state                Include current state
              lmc export myprogram -o shared.lmcbundle    Export to specific file
              lmc export myprogram --description "Demo"   Add a description
            """
    )

    @OptionGroup var globalOptions: GlobalOptions

    @Argument(
        help: "Name or path of the program to export",
        completion: .file(extensions: ["json"])
    )
    var program: String

    @Option(
        name: [.short, .long],
        help: "Output file path (defaults to <program>.lmcbundle)"
    )
    var output: String?

    @Option(
        name: .long,
        help: "Description to include in the export metadata"
    )
    var description: String?

    @Flag(
        name: .long,
        help: "Include the current state in the export"
    )
    var state: Bool = false

    @Flag(
        name: .long,
        help: "Output raw JSON to stdout instead of saving to file"
    )
    var stdout: Bool = false

    func perform(context: CommandContext) async throws {
        let snapshotService = context.services.snapshot

        // Export the program
        let exportData = try await snapshotService.exportProgram(
            name: program,
            includeState: state,
            description: description
        )

        if stdout {
            // Output to stdout
            FileHandle.standardOutput.write(exportData)
            if exportData.last != UInt8(ascii: "\n") {
                FileHandle.standardOutput.write(Data("\n".utf8))
            }
        } else {
            // Determine output filename
            let outputName: String
            if let specified = output {
                outputName = specified
            } else {
                // Extract base name from program reference
                let baseName = (program as NSString)
                    .deletingPathExtension
                    .components(separatedBy: "/")
                    .last ?? program
                outputName = "\(baseName).lmcbundle"
            }

            // Write to file
            let outputURL = URL(fileURLWithPath: outputName)
            try exportData.write(to: outputURL)

            // Calculate size for display
            let formatter = ByteCountFormatter()
            formatter.allowedUnits = [.useKB, .useBytes]
            formatter.countStyle = .file
            let sizeString = formatter.string(fromByteCount: Int64(exportData.count))

            print("✓ Exported to \(outputURL.lastPathComponent) (\(sizeString))")

            // Show what was included
            var included: [String] = ["program"]
            if state { included.append("state") }

            // Check if assembly and breakpoints were included
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            if let bundle = try? decoder.decode(SnapshotService.ExportBundle.self, from: exportData) {
                if bundle.assembly != nil { included.append("assembly") }
                if let breakpoints = bundle.breakpoints, !breakpoints.isEmpty {
                    included.append("\(breakpoints.count) breakpoint\(breakpoints.count == 1 ? "" : "s")")
                }
            }

            print("  Included: \(included.joined(separator: ", "))")
        }
    }
}