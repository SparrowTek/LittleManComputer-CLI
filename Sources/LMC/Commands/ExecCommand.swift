@preconcurrency import ArgumentParser
import CoreLittleManComputer
import Foundation

struct ExecCommand: LMCContextualCommand {
    static let configuration = CommandConfiguration(
        abstract: "Assemble inline source and execute it immediately"
    )

    @OptionGroup
    var globalOptions: GlobalOptions

    @Argument(parsing: .captureForPassthrough, help: "Inline Little Man Computer source to assemble and run")
    var source: [String]

    @Option(name: .long, help: "Comma-separated inbox values to preload")
    var input: String?

    @Option(name: .long, help: "Target cycles-per-second when running continuously")
    var speed: Double?

    @Option(name: .long, help: "Abort after the specified number of executed cycles")
    var maxCycles: Int?

    func perform(context: CommandContext) async throws {
        let inlineSource = source.joined(separator: " ")
        guard !inlineSource.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ValidationError("Provide inline source to execute.")
        }

        let assemblyRequest = AssemblyService.Request(source: .inline(inlineSource),
                                                      outputFormat: .text,
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

        let inboxValues = try parseInbox()

        let runRequest = ExecutionService.RunRequest(source: .snapshot(assemblyResponse.snapshot),
                                                     inbox: inboxValues,
                                                     speed: speed,
                                                     maxCycles: maxCycles,
                                                     breakpoints: [],
                                                     plainOutput: true)

        let outcome: ExecutionService.Outcome
        do {
            outcome = try await context.services.execution.run(runRequest)
        } catch let error as ExecutionService.Error {
            emitError(error.description)
            throw ExitCode(LMCExitCode.runtimeError.rawValue)
        } catch let error as ExecutionError {
            emitError(describeExecutionError(error))
            throw ExitCode(LMCExitCode.runtimeError.rawValue)
        } catch {
            emitError(error.localizedDescription)
            throw ExitCode(LMCExitCode.runtimeError.rawValue)
        }

        let presenter = StatePresenter(context: context)
        presenter.renderState(state: outcome.state,
                              program: assemblyResponse.program,
                              highlight: outcome.state.counter,
                              includeLabels: false,
                              forcePlain: context.globalOptions.plain)

        if !outcome.state.trace.isEmpty {
            presenter.printTrace(entries: outcome.state.trace, limit: 10, forcePlain: context.globalOptions.plain)
        }
    }

    private func parseInbox() throws -> [Int] {
        guard let input else { return [] }
        let tokens = input.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        return try tokens.map { piece in
            guard let value = Int(piece) else {
                throw ValidationError("Invalid inbox value: \(piece)")
            }
            return value
        }
    }

    private func describeExecutionError(_ error: ExecutionError) -> String {
        switch error {
        case .halted:
            return "Program already halted."
        case .awaitingInput:
            return "Program is awaiting additional inbox input."
        case .mailboxOutOfBounds(let address):
            return "Mailbox \(address.rawValue) is out of bounds."
        case .invalidInstruction(let word):
            return "Invalid instruction word: \(word.rawValue)."
        case .numericError(let numericError):
            return "Numeric error: \(numericError)."
        case .breakpointHit(let address):
            return "Breakpoint hit at mailbox \(address.rawValue)."
        }
    }
}
