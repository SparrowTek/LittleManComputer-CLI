import CoreLittleManComputer
import Foundation

final class REPLSession {
    private let context: CommandContext
    private let presenter: StatePresenter
    private var program: Program?
    private var programName: String?
    private var state = ProgramState()
    private var inbox: [Int] = []
    private var traceTail = 10
    private let history: CommandHistory

    init(context: CommandContext) {
        self.context = context
        self.presenter = StatePresenter(context: context)
        self.history = CommandHistory()
    }

    func run(welcome: String?, script: String?) async throws {
        if let welcome, !welcome.isEmpty {
            try printFileIfExists(at: welcome)
        }

        if let script, !script.isEmpty {
            try await processScript(at: script)
        }

        print("Type 'help' for a list of commands.\n")

        while true {
            prompt()
            guard let line = readLine(strippingNewline: true) else { break }
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty { continue }

            // Add to history if not a duplicate of the last command
            history.add(trimmed)

            do {
                if try await !handle(line: trimmed) {
                    break
                }
            } catch {
                FileHandle.standardError.write(Data("Error: \(error)\n".utf8))
            }
        }
    }

    private func prompt() {
        let status = programName ?? "<none>"
        FileHandle.standardOutput.write(Data("lmc(\(status))> ".utf8))
    }

    private func handle(line: String) async throws -> Bool {
        let components = tokenize(line)
        guard let command = components.first?.lowercased() else {
            return true
        }

        switch command {
        case "help", "?":
            print(helpText)
            return true
        case "quit", "exit":
            return false
        case "load":
            try loadProgram(from: remainder(of: line, removing: command))
            return true
        case "assemble":
            try await assemble(source: remainder(of: line, removing: command))
            return true
        case "run":
            try await runProgram(arguments: Array(components.dropFirst()))
            return true
        case "step":
            try await stepProgram(arguments: Array(components.dropFirst()))
            return true
        case "state":
            let focus = components.dropFirst().first.flatMap { Int($0) }
            showState(highlight: focus)
            return true
        case "trace":
            if let value = components.dropFirst().first, let count = Int(value) {
                traceTail = max(1, count)
            }
            showTrace()
            return true
        case "inbox":
            try configureInbox(Array(components.dropFirst()))
            return true
        case "reset":
            resetState()
            print("State reset.")
            return true
        case "break":
            try await handleBreakpointCommand(Array(components.dropFirst()))
            return true
        case "save":
            try await handleSaveCommand(Array(components.dropFirst()))
            return true
        case "history":
            handleHistoryCommand(Array(components.dropFirst()))
            return true
        default:
            print("Unknown command: \(command). Type 'help' for options.")
            return true
        }
    }

    private func loadProgram(from reference: String) throws {
        let trimmed = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CLIValidationError("Provide a snapshot name or path to load.")
        }
        let url = try context.services.snapshot.resolveProgramURL(for: trimmed)
        let data = try Data(contentsOf: url)
        let snapshot = try JSONDecoder().decode(ProgramSnapshot.self, from: data)
        let program = try Program(snapshot: snapshot)
        self.program = program
        self.programName = url.deletingPathExtension().lastPathComponent
        resetState(with: program)
        print("Loaded \(programName ?? "program").")
    }

    private func assemble(source: String) async throws {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw CLIValidationError("Provide inline source or a file path.")
        }

        let fm = FileManager.default
        let pathCandidate = (trimmed as NSString).expandingTildeInPath
        let assembleRequest: AssemblyService.Request
        if fm.fileExists(atPath: pathCandidate) {
            assembleRequest = AssemblyService.Request(source: .file(URL(fileURLWithPath: pathCandidate)),
                                                      outputFormat: .json,
                                                      labelStyle: .symbolic)
        } else {
            assembleRequest = AssemblyService.Request(source: .inline(trimmed),
                                                      outputFormat: .json,
                                                      labelStyle: .symbolic)
        }

        let response = try await context.services.assembly.assemble(assembleRequest)
        program = response.program
        programName = "inline"
        resetState(with: response.program)
        print("Program assembled and ready (\(response.program.usedRange.count) words).")
    }

    private func runProgram(arguments: [String]) async throws {
        guard let program else {
            throw CLIValidationError("Load or assemble a program first.")
        }
        let (maxCycles, speed, breakpoints) = parseRunOptions(arguments)

        // Set up async event collection and display
        let eventCollector = REPLEventCollector()
        let eventObserver = REPLEventObserver(
            outputHandler: { value in
                // Display output immediately with a distinct marker
                print("📤 Output: \(value)")
                eventCollector.recordOutput(value)
            },
            breakpointHandler: { address in
                // Display breakpoint hit immediately
                print("⚠️ Breakpoint hit at mailbox \(address.rawValue.zeroPadded)")
                eventCollector.recordBreakpoint(address)
            },
            inputHandler: {
                // Could potentially prompt for input here in the future
                print("📥 Input requested")
            },
            errorHandler: { message in
                print("❌ Error: \(message)")
                eventCollector.recordError(message)
            }
        )

        // Prepare the execution with our event observer
        let prepared = try context.services.execution.prepareEngine(
            ExecutionService.RunRequest(
                source: .snapshot(program.snapshot()),
                inbox: inbox,
                speed: speed,
                maxCycles: maxCycles,
                breakpoints: breakpoints,
                plainOutput: false,
                initialState: state
            ),
            additionalObserver: eventObserver
        )

        // Run the engine
        do {
            if let speed = speed {
                let schedule = ExecutionSchedule.hertz(speed)
                try await prepared.engine.run(schedule: schedule, maxCycles: maxCycles)
            } else {
                _ = try prepared.engine.runUntilHalt(maxCycles: maxCycles)
            }
        } catch let error as ExecutionError {
            if case .breakpointHit = error {
                // Breakpoint already displayed by observer
            } else {
                throw error
            }
        }

        // Update state
        state = prepared.engine.state
        inbox = state.inbox

        // Display final state
        presenter.renderState(state: state,
                              program: program,
                              highlight: state.counter,
                              includeLabels: !context.compactOutput,
                              forcePlain: context.globalOptions.plain)
        presenter.printTrace(entries: state.trace, limit: traceTail, forcePlain: context.globalOptions.plain)

        // Show summary of events if any occurred
        let outputs = eventCollector.getOutputs()
        if !outputs.isEmpty && outputs.count > 1 {
            print("\nTotal outputs produced: \(outputs.count)")
        }
    }

    private func stepProgram(arguments: [String]) async throws {
        guard let program else {
            throw CLIValidationError("Load or assemble a program first.")
        }

        let steps: Int
        if let first = arguments.first, let value = Int(first) {
            steps = max(1, value)
        } else {
            steps = 1
        }

        // Set up async event display for stepping
        let eventCollector = REPLEventCollector()
        let eventObserver = REPLEventObserver(
            outputHandler: { value in
                print("📤 Output: \(value)")
                eventCollector.recordOutput(value)
            },
            breakpointHandler: { address in
                print("⚠️ Breakpoint hit at mailbox \(address.rawValue.zeroPadded)")
                eventCollector.recordBreakpoint(address)
            },
            inputHandler: {
                print("📥 Input requested")
            },
            errorHandler: { message in
                print("❌ Error: \(message)")
                eventCollector.recordError(message)
            }
        )

        // Get any breakpoints from run options
        let (_, _, breakpoints) = parseRunOptions(arguments)

        // Prepare and execute
        let prepared = try context.services.execution.prepareEngine(
            ExecutionService.RunRequest(
                source: .snapshot(program.snapshot()),
                inbox: inbox,
                speed: nil,
                maxCycles: steps,
                breakpoints: breakpoints,
                plainOutput: false,
                initialState: state
            ),
            additionalObserver: eventObserver
        )

        do {
            _ = try prepared.engine.runUntilHalt(maxCycles: steps)
        } catch let error as ExecutionError {
            if case .breakpointHit = error {
                // Already displayed by observer
            } else {
                throw error
            }
        }

        // Update state
        state = prepared.engine.state
        inbox = state.inbox

        // Display final state
        presenter.renderState(state: state,
                              program: program,
                              highlight: state.counter,
                              includeLabels: !context.compactOutput,
                              forcePlain: context.globalOptions.plain)
        presenter.printTrace(entries: state.trace, limit: min(steps, traceTail), forcePlain: context.globalOptions.plain)
    }

    private func showState(highlight: Int?) {
        if let highlight, !MailboxAddress.validRange.contains(highlight) {
            print("Mailbox \(highlight) out of range 0..<\(MailboxAddress.validRange.upperBound)")
            return
        }
        let highlightAddress = highlight.map(MailboxAddress.init)
        presenter.renderState(state: state,
                              program: program,
                              highlight: highlightAddress,
                              includeLabels: program != nil && !context.compactOutput,
                              forcePlain: context.globalOptions.plain)
    }

    private func showTrace() {
        presenter.printTrace(entries: state.trace, limit: traceTail, forcePlain: context.globalOptions.plain)
    }

    private func configureInbox(_ arguments: [String]) throws {
        guard let first = arguments.first else {
            print("Inbox: \(inbox)")
            return
        }
        if first.lowercased() == "clear" {
            inbox.removeAll()
            print("Inbox cleared.")
            return
        }
        inbox = try parseValues(from: arguments.joined(separator: " "))
        print("Inbox set to \(inbox)")
    }

    private func parseRunOptions(_ arguments: [String]) -> (Int?, Double?, [MailboxAddress]) {
        var maxCycles: Int?
        var speed: Double?
        var breakpoints: [MailboxAddress] = []
        var index = 0
        let args = arguments
        while index < args.count {
            let token = args[index]
            switch token {
            case "--max", "-m":
                if index + 1 < args.count, let value = Int(args[index + 1]) {
                    maxCycles = value
                    index += 1
                }
            case "--speed", "-s":
                if index + 1 < args.count, let value = Double(args[index + 1]) {
                    speed = value
                    index += 1
                }
            case "--break", "-b":
                if index + 1 < args.count, let value = Int(args[index + 1]), MailboxAddress.validRange.contains(value) {
                    breakpoints.append(MailboxAddress(value))
                    index += 1
                }
            default:
                break
            }
            index += 1
        }
        return (maxCycles, speed, breakpoints)
    }

    private func resetState(with program: Program? = nil) {
        if let program {
            state = ProgramState()
            state.ensureMemoryInitialized(with: program.memoryImage)
        } else {
            state = ProgramState()
        }
        inbox.removeAll()
    }

    private func printFileIfExists(at path: String) throws {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return }
        let contents = try String(contentsOfFile: expanded)
        print(contents)
    }

    private func processScript(at path: String) async throws {
        let expanded = (path as NSString).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else {
            throw CLIValidationError("Script file not found: \(path)")
        }
        let contents = try String(contentsOfFile: expanded)
        let lines = contents.split(separator: "\n", omittingEmptySubsequences: false)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
            _ = try await handle(line: trimmed)
        }
    }

    private func parseValues(from raw: String) throws -> [Int] {
        let tokens = raw.split(whereSeparator: { $0 == "," || $0.isWhitespace })
        return try tokens.map { token in
            guard let value = Int(token) else {
                throw CLIValidationError("Invalid numeric value: \(token)")
            }
            return value
        }
    }

    private func tokenize(_ line: String) -> [String] {
        var results: [String] = []
        var current = ""
        var inQuotes = false
        for char in line {
            if char == "\"" {
                inQuotes.toggle()
                continue
            }
            if char.isWhitespace && !inQuotes {
                if !current.isEmpty {
                    results.append(current)
                    current.removeAll(keepingCapacity: true)
                }
            } else {
                current.append(char)
            }
        }
        if !current.isEmpty {
            results.append(current)
        }
        return results
    }

    private func remainder(of line: String, removing command: String) -> String {
        line.dropFirst(command.count).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var helpText: String {
        """
        Commands:
          load <name|path>           Load a program snapshot from workspace or path
          assemble <source|path>     Assemble inline source or file and load it
          run [--max N] [--speed HZ] Execute the current program (continues state)
          step [N]                   Execute N cycles (default 1)
          state [mailbox]            Show current state with optional mailbox highlight
          trace [N]                  Show last N trace entries (default 10)
          inbox <values|clear>       Configure inbox values for the next run
          reset                      Clear state and inbox for the loaded program
          save <name> [--state]      Save program (and optionally state) to workspace
          break add <addr...>        Add persistent breakpoints
          break remove <addr...>     Remove persistent breakpoints
          break clear                Clear all breakpoints for current program
          break list                 List breakpoints for current program
          history [N|clear|search]   Show command history (last N entries)
          help                       Show this help message
          quit                       Exit the REPL
        """
    }
}

private struct CLIValidationError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

extension REPLSession {
    private func handleHistoryCommand(_ args: [String]) {
        if let first = args.first {
            switch first.lowercased() {
            case "clear":
                history.clear()
                print("Command history cleared.")
            case "search":
                guard args.count > 1 else {
                    print("Usage: history search <pattern>")
                    return
                }
                let pattern = args.dropFirst().joined(separator: " ")
                let matches = history.search(containing: pattern)
                if matches.isEmpty {
                    print("No matching commands found.")
                } else {
                    print("Matching commands:")
                    for cmd in matches {
                        print("  \(cmd)")
                    }
                }
            default:
                if let count = Int(first) {
                    print(history.formatHistory(numbered: true, recent: count))
                } else {
                    print("Invalid history option: \(first)")
                    print("Usage: history [N|clear|search <pattern>]")
                }
            }
        } else {
            // Show recent history with default count
            print(history.formatHistory(numbered: true, recent: 20))
        }
    }

    private func handleBreakpointCommand(_ args: [String]) async throws {
        guard let program = program else {
            print("No program loaded. Use 'load' or 'assemble' first.")
            return
        }

        guard let subcommand = args.first else {
            print("Usage: break <add|remove|clear|list> [addresses...]")
            return
        }

        let breakpointStore = context.services.breakpoints

        switch subcommand.lowercased() {
        case "add":
            let addresses = try args.dropFirst().map { arg -> Int in
                guard let value = Int(arg) else {
                    throw CLIValidationError("Invalid address '\(arg)': must be an integer")
                }
                guard MailboxAddress.validRange.contains(value) else {
                    throw CLIValidationError("Address \(value) out of range: must be 0-99")
                }
                return value
            }
            guard !addresses.isEmpty else {
                print("Provide at least one address to add")
                return
            }
            try breakpointStore.addBreakpoints(addresses, to: program, name: programName)
            let addressList = addresses.map { String(format: "%03d", $0) }.joined(separator: ", ")
            print("Added breakpoints at mailboxes \(addressList)")

        case "remove":
            let addresses = try args.dropFirst().map { arg -> Int in
                guard let value = Int(arg) else {
                    throw CLIValidationError("Invalid address '\(arg)': must be an integer")
                }
                guard MailboxAddress.validRange.contains(value) else {
                    throw CLIValidationError("Address \(value) out of range: must be 0-99")
                }
                return value
            }
            guard !addresses.isEmpty else {
                print("Provide at least one address to remove")
                return
            }
            try breakpointStore.removeBreakpoints(addresses, from: program)
            let addressList = addresses.map { String(format: "%03d", $0) }.joined(separator: ", ")
            print("Removed breakpoints at mailboxes \(addressList)")

        case "clear":
            try breakpointStore.clearBreakpoints(for: program)
            print("Cleared all breakpoints for the program")

        case "list":
            let breakpoints = breakpointStore.getBreakpoints(for: program)
            if breakpoints.isEmpty {
                print("No breakpoints set for this program")
            } else {
                print("Breakpoints:")
                for bp in breakpoints {
                    print("  • Mailbox \(String(format: "%03d", bp.rawValue))")
                }
            }

        default:
            print("Unknown breakpoint subcommand: \(subcommand)")
            print("Usage: break <add|remove|clear|list> [addresses...]")
        }
    }
}

extension REPLSession {
    private func handleSaveCommand(_ args: [String]) async throws {
        guard let program = program else {
            print("No program loaded. Use 'load' or 'assemble' first.")
            return
        }

        guard let name = args.first else {
            print("Usage: save <name> [--state]")
            print("  save myprogram         Save just the program")
            print("  save myprogram --state Save both program and current state")
            return
        }

        let saveState = args.contains("--state")
        let snapshotService = context.services.snapshot

        // Save the program snapshot
        let programSnapshot = ProgramSnapshot(program: program)
        let storeRequest = SnapshotService.StoreRequest(
            name: name,
            snapshot: programSnapshot,
            assembly: nil  // Could potentially store assembly if we tracked it
        )

        do {
            let programURL = try await snapshotService.store(storeRequest)
            print("✓ Saved program to \(programURL.lastPathComponent)")

            // Save state if requested
            if saveState {
                let stateSnapshot = ProgramStateSnapshot(state: state)
                let stateRequest = SnapshotService.StoreStateRequest(
                    name: name + "-state",
                    stateSnapshot: stateSnapshot,
                    programSnapshot: programSnapshot
                )

                let stateURL = try await snapshotService.storeState(stateRequest)
                print("✓ Saved state to \(stateURL.lastPathComponent)")
            }

            // Update the program name for the prompt
            programName = name
        } catch {
            print("Failed to save: \(error)")
        }
    }
}

private extension Int {
    var zeroPadded: String {
        String(format: "%03d", self)
    }
}
