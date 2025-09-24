@preconcurrency import ArgumentParser
import Foundation

struct SnapshotCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Manage persisted Little Man Computer snapshots",
        subcommands: [Store.self, List.self, Remove.self]
    )

    func run() throws {
        throw CleanExit.helpRequest(Self.self)
    }

    struct Store: LMCContextualCommand {
        static let configuration = CommandConfiguration(
            abstract: "Assemble source and store it in the workspace snapshot cache"
        )

        @OptionGroup
        var globalOptions: GlobalOptions

        @Option(name: .long, help: "Name to store the compiled snapshot under")
        var name: String

        @Option(name: .long, help: "Path to .lmc source file. Reads stdin when omitted.")
        var source: String?

        @Option(name: .long, help: "Output format to persist alongside the snapshot")
        var format: AssemblyService.OutputFormat = .json

        func perform(context: CommandContext) async throws {
            let assemblySource: AssemblyService.Request.Source
            if let source {
                assemblySource = .file(URL(fileURLWithPath: source))
            } else {
                assemblySource = .stdin
            }

            let assemblyRequest = AssemblyService.Request(source: assemblySource,
                                                          outputFormat: format,
                                                          labelStyle: .symbolic)
            let assemblyResponse: AssemblyService.Response
            do {
                assemblyResponse = try await context.services.assembly.assemble(assemblyRequest)
            } catch let error as AssemblyService.Error {
                emitError(error.description)
                throw ExitCode(LMCExitCode.assemblyError.rawValue)
            } catch {
                emitError(error.localizedDescription)
                throw ExitCode(LMCExitCode.assemblyError.rawValue)
            }

            let storeRequest = SnapshotService.StoreRequest(name: name,
                                                            snapshot: assemblyResponse.snapshot,
                                                            assembly: format == .text ? assemblyResponse.renderedAssembly : nil)
            do {
                let url = try await context.services.snapshot.store(storeRequest)
                print("Stored snapshot \(name) at \(url.path)")
            } catch let error as SnapshotService.Error {
                emitError(error.description)
                throw ExitCode(LMCExitCode.ioError.rawValue)
            } catch {
                emitError(error.localizedDescription)
                throw ExitCode(LMCExitCode.ioError.rawValue)
            }
        }
    }

    struct List: LMCContextualCommand {
        static let configuration = CommandConfiguration(
            abstract: "List stored snapshots and their metadata"
        )

        @OptionGroup
        var globalOptions: GlobalOptions

        func perform(context: CommandContext) async throws {
            let entries: [SnapshotService.ListEntry]
            do {
                entries = try context.services.snapshot.listSnapshots()
            } catch let error as SnapshotService.Error {
                emitError(error.description)
                throw ExitCode(LMCExitCode.ioError.rawValue)
            } catch {
                emitError(error.localizedDescription)
                throw ExitCode(LMCExitCode.ioError.rawValue)
            }

            if entries.isEmpty {
                print("No snapshots stored in \(context.environment.workspace.path)")
                return
            }

            let formatter = ISO8601DateFormatter()
            for entry in entries {
                let created = formatter.string(from: entry.programMetadata.createdAt)
                print("\(entry.name)\tcreated: \(created)")
            }
        }
    }

    struct Remove: LMCContextualCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove snapshots by name"
        )

        @OptionGroup
        var globalOptions: GlobalOptions

        @Argument(help: "One or more snapshot names to delete")
        var names: [String]

        @Flag(name: .long, help: "Skip confirmation prompts")
        var force: Bool = false

        func perform(context: CommandContext) async throws {
            guard !names.isEmpty else {
                throw ValidationError("Provide at least one snapshot name to remove.")
            }

            if !force {
                print("Remove \(names.count) snapshot(s): \(names.joined(separator: ", "))? [y/N] ", terminator: "")
                guard let line = readLine(), ["y", "yes"].contains(line.lowercased()) else {
                    throw CleanExit.message("Aborted")
                }
            }

            do {
                try context.services.snapshot.removeSnapshots(named: names)
            } catch let error as SnapshotService.Error {
                emitError(error.description)
                throw ExitCode(LMCExitCode.ioError.rawValue)
            } catch {
                emitError(error.localizedDescription)
                throw ExitCode(LMCExitCode.ioError.rawValue)
            }

            print("Removed \(names.count) snapshot(s).")
        }
    }
}
