import ConsoleKitTerminal
import CoreLittleManComputer
import Foundation

struct StatePresenter {
    private let context: CommandContext
    private let asciiRenderer = StateRenderer()

    init(context: CommandContext) {
        self.context = context
    }

    func renderState(state: ProgramState,
                     program: Program?,
                     highlight: MailboxAddress?,
                     includeLabels: Bool,
                     forcePlain: Bool = false) {
        if !forcePlain, let terminal = context.terminal {
            let palette = context.theme.palette(colored: shouldUseColor(with: terminal))
            let renderer = ConsoleStateRenderer(terminal: terminal, palette: palette)
            renderer.render(state: state,
                            program: program,
                            options: .init(highlightMailbox: highlight,
                                           showLabels: includeLabels,
                                           compact: context.compactOutput))
        } else {
            let text = asciiRenderer.render(state: state,
                                            program: program,
                                            options: .init(highlightMailbox: highlight,
                                                           showLabels: includeLabels,
                                                           plainOutput: true,
                                                           compact: context.compactOutput))
            print(text)
        }
    }

    func printTrace(entries: [ProgramState.TraceEntry], limit: Int, forcePlain: Bool = false) {
        let tail = Array(entries.suffix(limit))
        guard !tail.isEmpty else {
            if !forcePlain, context.terminal != nil {
                context.terminal?.output("No trace entries recorded.".consoleText(palette().traceText), newLine: true)
            } else {
                print("No trace entries recorded.")
            }
            return
        }

        let label = "Trace (last \(tail.count))"
        let formatter = TraceFormatter(style: .singleLine, includeHeader: true)
        let rendered = formatter.render(tail)

        if !forcePlain, let terminal = context.terminal {
            let palette = self.palette()
            terminal.output("".consoleText(), newLine: true)
            terminal.output(label.consoleText(palette.traceHeader), newLine: true)
            for line in rendered.split(separator: "\n", omittingEmptySubsequences: false) {
                terminal.output(String(line).consoleText(palette.traceText), newLine: true)
            }
        } else {
            print("")
            print(label)
            print(rendered)
        }
    }

    func printEvents(_ events: [ExecutionEvent], limit: Int, forcePlain: Bool = false) {
        let tail = Array(events.suffix(limit))
        guard !tail.isEmpty else { return }

        if !forcePlain, let terminal = context.terminal {
            let palette = self.palette()
            terminal.output("".consoleText(), newLine: true)
            terminal.output("Events (last \(tail.count))".consoleText(palette.eventHeader), newLine: true)
            for event in tail {
                terminal.output(describe(event: event).consoleText(palette.eventText), newLine: true)
            }
        } else {
            print("")
            print("Events (last \(tail.count))")
            tail.forEach { print(describe(event: $0)) }
        }
    }

    // MARK: - Helpers

    private func palette() -> TerminalPalette {
        guard let terminal = context.terminal else { return .plain }
        let colored = shouldUseColor(with: terminal)
        return context.theme.palette(colored: colored)
    }

    private func shouldUseColor(with terminal: Terminal) -> Bool {
        switch context.globalOptions.effectiveColorMode {
        case .never:
            return false
        case .always:
            return true
        case .auto:
            return terminal.supportsANSICommands
        }
    }

    private func describe(event: ExecutionEvent) -> String {
        switch event {
        case .cycleStarted(let cycle, let counter):
            return "Cycle \(cycle) started at mailbox \(String(format: "%03d", counter.rawValue))"
        case .instructionDecoded(let instruction):
            return "Decoded \(instruction.opcode.metadata.mnemonic)"
        case .instructionExecuted(let instruction, _):
            return "Executed \(instruction.opcode.metadata.mnemonic)"
        case .cycleCompleted(let cycle, _):
            return "Cycle \(cycle) completed"
        case .inputRequested:
            return "Input requested"
        case .outputProduced(let value):
            return "Output produced: \(value)"
        case .breakpointHit(let address):
            return "Breakpoint signalled at \(String(format: "%03d", address.rawValue))"
        case .halted:
            return "Program halted"
        case .error(let message):
            return "Error: \(message)"
        }
    }
}
