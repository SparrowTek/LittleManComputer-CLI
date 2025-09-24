@preconcurrency import ArgumentParser
import Foundation

struct DisassembleCommand: LMCContextualCommand {
    static let configuration = CommandConfiguration(
        abstract: "Disassemble a saved program snapshot into human-readable assembly"
    )

    @OptionGroup
    var globalOptions: GlobalOptions

    @Argument(help: "Path to a program snapshot or named snapshot")
    var program: String

    @Option(name: [.customShort("o"), .long], help: "Write assembly output to file. Defaults to stdout.")
    var output: String?

    @Flag(name: .long, help: "Annotate listing with addresses and metadata")
    var annotate: Bool = false

    func perform(context: CommandContext) async throws {
        let programURL: URL
        do {
            programURL = try context.services.snapshot.resolveProgramURL(for: program)
        } catch let error as SnapshotService.Error {
            throw ValidationError(error.description)
        }

        let request = AssemblyService.DisassemblyRequest(snapshotURL: programURL,
                                                          annotate: annotate)

        let response: AssemblyService.DisassemblyResponse
        do {
            response = try await context.services.assembly.disassemble(request)
        } catch let error as AssemblyService.Error {
            emitError(error.description)
            throw ExitCode(LMCExitCode.ioError.rawValue)
        } catch {
            emitError(error.localizedDescription)
            throw ExitCode(LMCExitCode.ioError.rawValue)
        }

        if let output {
            let url = URL(fileURLWithPath: output)
            do {
                try write(response.assembly, to: url)
            } catch {
                emitError("Failed to write disassembly: \(error.localizedDescription)")
                throw ExitCode(LMCExitCode.ioError.rawValue)
            }
            print("Wrote disassembly to \(url.path)")
        } else {
            print(response.assembly)
        }
    }

    private func write(_ text: String, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !directory.path.isEmpty && directory.path != "." {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
