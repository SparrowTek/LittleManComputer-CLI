@preconcurrency import ArgumentParser
import CoreLittleManComputer
import Foundation

struct StateCommand: LMCContextualCommand {
    static let configuration = CommandConfiguration(
        abstract: "Inspect the state of a program snapshot"
    )

    @OptionGroup
    var globalOptions: GlobalOptions

    @Argument(help: "Path to a state snapshot or program snapshot")
    var program: String

    @Flag(name: .long, help: "Emit JSON instead of formatted text")
    var json: Bool = false

    @Option(name: .long, help: "Tail length for recent instruction trace")
    var trace: Int = 10

    @Option(name: .long, help: "Focus on a specific mailbox when printing state")
    var mailbox: Int?

    func perform(context: CommandContext) async throws {
        let url: URL
        do {
            url = try context.services.snapshot.resolveSnapshotURL(for: program)
        } catch let error as SnapshotService.Error {
            throw ValidationError(error.description)
        }

        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        let state: ProgramState
        var programObject: Program?
        do {
            if let stateSnapshot = try? decoder.decode(ProgramStateSnapshot.self, from: data) {
                state = try ProgramState(snapshot: stateSnapshot)
                if let candidate = try? context.services.snapshot.findProgramCompanion(for: url) {
                    programObject = candidate
                }
            } else {
                let programSnapshot = try decoder.decode(ProgramSnapshot.self, from: data)
                programObject = try Program(snapshot: programSnapshot)
                var baseState = ProgramState()
                baseState.ensureMemoryInitialized(with: programObject!.memoryImage)
                state = baseState
            }
        } catch {
            emitError("Unable to decode snapshot at \(url.path): \(error.localizedDescription)")
            throw ExitCode(LMCExitCode.ioError.rawValue)
        }

        if json {
            let serializer = ProgramStateSerializer(prettyPrinted: true)
            do {
                let output = try serializer.exportJSON(state)
                FileHandle.standardOutput.write(output)
                if output.last != UInt8(ascii: "\n") {
                    FileHandle.standardOutput.write(Data("\n".utf8))
                }
            } catch {
                emitError("Failed to encode state snapshot: \(error.localizedDescription)")
                throw ExitCode(LMCExitCode.ioError.rawValue)
            }
            return
        }

        let highlightMailbox = try mailbox.map { value -> MailboxAddress in
            guard MailboxAddress.validRange.contains(value) else {
                throw ValidationError("Mailbox \(value) out of range 0..<\(MailboxAddress.validRange.upperBound)")
            }
            return MailboxAddress(value)
        }

        let presenter = StatePresenter(context: context)
        presenter.renderState(state: state,
                              program: programObject,
                              highlight: highlightMailbox,
                              includeLabels: programObject != nil && !context.compactOutput,
                              forcePlain: context.globalOptions.plain)

        if trace > 0 {
            presenter.printTrace(entries: state.trace, limit: trace, forcePlain: context.globalOptions.plain)
        }
    }
}
