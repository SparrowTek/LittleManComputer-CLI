@preconcurrency import ArgumentParser
import Foundation

struct AssembleCommand: LMCContextualCommand {
    static let configuration = CommandConfiguration(
        abstract: "Assemble Little Man Computer source into a snapshot"
    )

    @OptionGroup
    var globalOptions: GlobalOptions

    @Option(name: [.short, .long], help: "Path to .lmc source file. Reads stdin when omitted.")
    var input: String?

    @Option(name: [.customShort("o"), .long], help: "Write compiled output to file. Defaults to stdout.")
    var output: String?

    @Option(name: .long, help: "Select output format")
    var format: AssemblyService.OutputFormat = .json

    @Option(name: .long, help: "Control emitted label style in disassembly")
    var labelStyle: AssemblyService.LabelStyle = .symbolic

    func perform(context: CommandContext) async throws {
        let source: AssemblyService.Request.Source
        if let input {
            source = .file(URL(fileURLWithPath: input))
        } else {
            source = .stdin
        }

        let request = AssemblyService.Request(source: source,
                                              outputFormat: format,
                                              labelStyle: labelStyle)

        let response: AssemblyService.Response
        do {
            response = try await context.services.assembly.assemble(request)
        } catch let error as AssemblyService.Error {
            emitError(error.description)
            throw ExitCode(LMCExitCode.assemblyError.rawValue)
        } catch {
            emitError(error.localizedDescription)
            throw ExitCode(LMCExitCode.assemblyError.rawValue)
        }

        if let output {
            let url = URL(fileURLWithPath: output)
            do {
                try write(response: response, to: url)
            } catch {
                emitError("Failed to write output: \(error.localizedDescription)")
                throw ExitCode(LMCExitCode.ioError.rawValue)
            }
            print("Saved snapshot to \(url.path)")
        } else {
            write(response: response, to: FileHandle.standardOutput)
        }

        emitSummary(for: response)
    }

    private func write(response: AssemblyService.Response, to fileHandle: FileHandle) {
        switch format {
        case .json:
            fileHandle.write(response.json)
        case .text:
            let text = response.renderedAssembly ?? ""
            fileHandle.write(Data((text + "\n").utf8))
        }
    }

    private func write(response: AssemblyService.Response, to url: URL) throws {
        let directory = url.deletingLastPathComponent()
        if !directory.path.isEmpty && directory.path != "." {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        switch format {
        case .json:
            try response.json.write(to: url, options: .atomic)
        case .text:
            guard let rendered = response.renderedAssembly else { return }
            try rendered.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func emitSummary(for response: AssemblyService.Response) {
        let count = response.program.usedRange.count
        let labelCount = response.program.labels.count
        let message = "✓ Assembled program with \(count) words (labels: \(labelCount))\n"
        FileHandle.standardError.write(Data(message.utf8))
    }
}
