@preconcurrency import ArgumentParser
import CoreLittleManComputer
import Dispatch
import Foundation

private let defaultTraceTail = 10

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "Execute Little Man Computer programs",
        subcommands: [Execute.self, Step.self, Break.self],
        defaultSubcommand: Execute.self
    )

    struct Execute: LMCContextualCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run a program until halt or breakpoint"
        )

        @OptionGroup
        var globalOptions: GlobalOptions

        @Argument(help: "Path to a program snapshot or named snapshot")
        var program: String

        @Option(name: .long, help: "Comma-separated inbox values or 'stdin' for streaming input")
        var input: String?

        @Option(name: .long, help: "Target cycles-per-second when running continuously")
        var speed: Double?

        @Option(name: .long, help: "Abort after the specified number of executed cycles")
        var maxCycles: Int?

        @Option(name: .long, parsing: .upToNextOption, help: "One or more mailbox addresses to break on")
        var breakpoints: [Int] = []

        @Flag(name: .long, help: "Emit plain state snapshots instead of grid rendering")
        var plainState: Bool = false

        @Option(name: .long, help: "Write JSON event log to file")
        var log: String?

        func perform(context: CommandContext) async throws {
            let programURL = try context.services.snapshot.resolveProgramURL(for: program)
            let inboxValues = try parseInboxArgument(input)
            let breakpointAddresses = try convertBreakpoints(breakpoints)

            let request = ExecutionService.RunRequest(source: .programURL(programURL),
                                                      inbox: inboxValues,
                                                      speed: speed,
                                                      maxCycles: maxCycles,
                                                      breakpoints: breakpointAddresses,
                                                      plainOutput: plainState || context.globalOptions.plain)

            let plainOverride = plainState || context.globalOptions.plain
            let presenter = StatePresenter(context: context)
            let shouldStream = !plainOverride && !context.compactOutput && context.terminal != nil

            let logger = try createLogger()
            defer { logger?.close() }

            let prepared = try context.services.execution.prepareEngine(request, additionalObserver: logger)
            let engine = prepared.engine
            let program = prepared.program

            let stateLoggingTask: Task<Void, Never>?
            if logger != nil || shouldStream {
                let streamingPresenter = presenter
                stateLoggingTask = Task {
                    for await snapshot in engine.stateStream(emitInitial: true) {
                        logger?.log(state: snapshot)
                        if shouldStream {
                            await MainActor.run {
                                context.terminal?.clear(.screen)
                                streamingPresenter.renderState(state: snapshot,
                                                               program: program,
                                                               highlight: snapshot.counter,
                                                               includeLabels: !context.compactOutput,
                                                               forcePlain: false)
                            }
                        }
                    }
                }
            } else {
                stateLoggingTask = nil
            }

            let schedule: ExecutionSchedule
            if let speed {
                guard speed > 0 else {
                    emitError("Speed must be greater than zero.")
                    stateLoggingTask?.cancel()
                    _ = await stateLoggingTask?.value
                    throw ExitCode(LMCExitCode.usage.rawValue)
                }
                schedule = .hertz(speed)
            } else {
                schedule = .unlimited
            }

            let runTask = Task<MailboxAddress?, Error> {
                do {
                    try await engine.run(schedule: schedule, maxCycles: request.maxCycles)
                    return nil
                } catch let error as ExecutionError {
                    if case .breakpointHit(let address) = error {
                        return address
                    }
                    throw error
                }
            }

            #if canImport(Darwin)
            let previousHandler = signal(SIGINT, SIG_IGN)
            let signalSource = DispatchSource.makeSignalSource(signal: SIGINT, queue: DispatchQueue.global())
            signalSource.setEventHandler {
                runTask.cancel()
            }
            signalSource.resume()
            #endif

            let breakpointAddress: MailboxAddress?
            do {
                breakpointAddress = try await runTask.value
            } catch is CancellationError {
                emitError("Execution interrupted.")
                stateLoggingTask?.cancel()
                _ = await stateLoggingTask?.value
                presenter.renderState(state: engine.state,
                                      program: program,
                                      highlight: engine.state.counter,
                                      includeLabels: !context.compactOutput,
                                      forcePlain: plainOverride)
                #if canImport(Darwin)
                signalSource.cancel()
                signal(SIGINT, previousHandler)
                #endif
                return
            } catch let error as ExecutionError {
                stateLoggingTask?.cancel()
                _ = await stateLoggingTask?.value
                emitError(describeExecutionError(error))
                #if canImport(Darwin)
                signalSource.cancel()
                signal(SIGINT, previousHandler)
                #endif
                throw ExitCode(LMCExitCode.runtimeError.rawValue)
            } catch {
                stateLoggingTask?.cancel()
                _ = await stateLoggingTask?.value
                emitError(error.localizedDescription)
                #if canImport(Darwin)
                signalSource.cancel()
                signal(SIGINT, previousHandler)
                #endif
                throw ExitCode(LMCExitCode.runtimeError.rawValue)
            }

            stateLoggingTask?.cancel()
            _ = await stateLoggingTask?.value

            #if canImport(Darwin)
            signalSource.cancel()
            signal(SIGINT, previousHandler)
            #endif

            if let breakpointAddress {
                FileHandle.standardError.write(Data("⚠️ Breakpoint hit at mailbox \(breakpointAddress.rawValue)\n".utf8))
            }

            if !shouldStream {
                presenter.renderState(state: engine.state,
                                      program: program,
                                      highlight: engine.state.counter,
                                      includeLabels: !context.compactOutput,
                                      forcePlain: plainOverride)
            }

            presenter.printTrace(entries: engine.state.trace,
                                 limit: defaultTraceTail,
                                 forcePlain: plainOverride)

            if context.globalOptions.effectiveVerbosity == .debug {
                presenter.printEvents(prepared.recorder.snapshot(),
                                      limit: 10,
                                      forcePlain: plainOverride)
            }
        }

        private func createLogger() throws -> EventJSONLogger? {
            guard let log else { return nil }
            let expanded = (log as NSString).expandingTildeInPath
            return try EventJSONLogger(url: URL(fileURLWithPath: expanded))
        }
    }

    struct Step: LMCContextualCommand {
        static let configuration = CommandConfiguration(
            abstract: "Execute a limited number of cycles"
        )

        @OptionGroup
        var globalOptions: GlobalOptions

        @Argument(help: "Path to a program snapshot or named snapshot")
        var program: String

        @Option(name: .long, help: "Comma-separated inbox values or 'stdin' for streaming input")
        var input: String?

        @Option(name: .long, help: "Number of cycles to execute (default 1)")
        var count: Int = 1

        @Option(name: .long, parsing: .upToNextOption, help: "Mailboxes to break on during stepping")
        var breakpoints: [Int] = []

        func perform(context: CommandContext) async throws {
            guard count > 0 else {
                emitError("Step count must be greater than zero.")
                throw ExitCode(LMCExitCode.usage.rawValue)
            }

            let programURL = try context.services.snapshot.resolveProgramURL(for: program)
            let inboxValues = try parseInboxArgument(input)
            let breakpointAddresses = try convertBreakpoints(breakpoints)

            let request = ExecutionService.RunRequest(source: .programURL(programURL),
                                                      inbox: inboxValues,
                                                      speed: nil,
                                                      maxCycles: count,
                                                      breakpoints: breakpointAddresses,
                                                      plainOutput: context.globalOptions.plain)

            let prepared = try context.services.execution.prepareEngine(request)
            do {
                try await prepared.engine.run(schedule: .unlimited, maxCycles: count)
            } catch let error as ExecutionError {
                if case .breakpointHit = error {
                    // breakpoint reached during step; continue to present state
                } else {
                    emitError(describeExecutionError(error))
                    throw ExitCode(LMCExitCode.runtimeError.rawValue)
                }
            }

            let presenter = StatePresenter(context: context)
            presenter.renderState(state: prepared.engine.state,
                                  program: prepared.program,
                                  highlight: prepared.engine.state.counter,
                                  includeLabels: !context.compactOutput,
                                  forcePlain: context.globalOptions.plain)
            presenter.printTrace(entries: prepared.engine.state.trace,
                                 limit: min(count, defaultTraceTail),
                                 forcePlain: context.globalOptions.plain)
        }
    }

    struct Break: LMCContextualCommand {
        static let configuration = CommandConfiguration(
            abstract: "Run until hitting the specified breakpoints"
        )

        @OptionGroup
        var globalOptions: GlobalOptions

        @Argument(help: "Path to a program snapshot or named snapshot")
        var program: String

        @Option(name: .long, parsing: .upToNextOption, help: "Mailbox addresses to break on")
        var address: [Int]

        @Option(name: .long, help: "Comma-separated inbox values or 'stdin' for streaming input")
        var input: String?

        @Option(name: .long, help: "Abort after the specified number of executed cycles")
        var maxCycles: Int?

        func perform(context: CommandContext) async throws {
            guard !address.isEmpty else {
                emitError("Provide at least one breakpoint address.")
                throw ExitCode(LMCExitCode.usage.rawValue)
            }

            let programURL = try context.services.snapshot.resolveProgramURL(for: program)
            let inboxValues = try parseInboxArgument(input)
            let breakpointAddresses = try convertBreakpoints(address)

            let request = ExecutionService.RunRequest(source: .programURL(programURL),
                                                      inbox: inboxValues,
                                                      speed: nil,
                                                      maxCycles: maxCycles,
                                                      breakpoints: breakpointAddresses,
                                                      plainOutput: context.globalOptions.plain)

            let prepared = try context.services.execution.prepareEngine(request)
            do {
                try await prepared.engine.run(schedule: .unlimited, maxCycles: maxCycles)
                emitError("Program halted before hitting a breakpoint.")
            } catch let error as ExecutionError {
                if case .breakpointHit(let address) = error {
                    FileHandle.standardError.write(Data("⚠️ Breakpoint hit at mailbox \(address.rawValue)\n".utf8))
                } else {
                    emitError(describeExecutionError(error))
                    throw ExitCode(LMCExitCode.runtimeError.rawValue)
                }
            }

            let presenter = StatePresenter(context: context)
            presenter.renderState(state: prepared.engine.state,
                                  program: prepared.program,
                                  highlight: prepared.engine.state.counter,
                                  includeLabels: !context.compactOutput,
                                  forcePlain: context.globalOptions.plain)
            presenter.printTrace(entries: prepared.engine.state.trace,
                                 limit: defaultTraceTail,
                                 forcePlain: context.globalOptions.plain)
        }
    }
}

private func parseInboxArgument(_ input: String?) throws -> [Int] {
    guard let input else { return [] }
    if input.lowercased() == "stdin" {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let text = String(decoding: data, as: UTF8.self)
        return try parseValues(from: text)
    }
    return try parseValues(from: input)
}

private func convertBreakpoints(_ values: [Int]) throws -> [MailboxAddress] {
    try values.map { value in
        guard MailboxAddress.validRange.contains(value) else {
            throw ValidationError("Breakpoint address \(value) out of range 0..<\(MailboxAddress.validRange.upperBound)")
        }
        return MailboxAddress(value)
    }
}

private func parseValues(from raw: String) throws -> [Int] {
    let tokens = raw.split(whereSeparator: { $0 == "," || $0.isWhitespace })
    return try tokens.map { token in
        guard let value = Int(token) else {
            throw ValidationError("Invalid numeric value: \(token)")
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
