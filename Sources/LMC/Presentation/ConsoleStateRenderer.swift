import ConsoleKitTerminal
import CoreLittleManComputer
import Foundation

struct ConsoleStateRenderer {
    struct Options {
        var highlightMailbox: MailboxAddress?
        var showLabels: Bool
        var compact: Bool
    }

    private let terminal: Terminal
    private let palette: TerminalPalette

    init(terminal: Terminal, palette: TerminalPalette) {
        self.terminal = terminal
        self.palette = palette
    }

    func render(state: ProgramState, program: Program?, options: Options) {
        renderSummary(state)

        if !options.compact {
            terminal.output("".consoleText(), newLine: true)
            terminal.output("Memory".consoleText(palette.header), newLine: true)
            renderGrid(state: state, highlight: highlightSet(counter: state.counter, extra: options.highlightMailbox))

            if options.showLabels, let program, !program.labels.isEmpty {
                terminal.output("".consoleText(), newLine: true)
                terminal.output("Labels".consoleText(palette.header), newLine: true)
                for (label, address) in program.labels.sorted(by: { $0.key.lowercased() < $1.key.lowercased() }) {
                    let line = "  \(label): ".consoleText(palette.label) + address.rawValue.zeroPadded.consoleText(palette.gridValue)
                    terminal.output(line, newLine: true)
                }
            }
        }

        if !state.outbox.isEmpty {
            terminal.output("".consoleText(), newLine: true)
            terminal.output("Outbox".consoleText(palette.header), newLine: true)
            let values = state.outbox.map(String.init).joined(separator: ", ")
            terminal.output("  \(values)".consoleText(palette.outboxValue), newLine: true)
        }
    }

    private func renderSummary(_ state: ProgramState) {
        let items: [(String, String)] = [
            ("Counter", state.counter.rawValue.zeroPadded),
            ("Accumulator", String(state.accumulator.value)),
            ("Halted", String(state.halted)),
            ("Cycles", String(state.cycles)),
            ("Inbox", state.inbox.isEmpty ? "(empty)" : state.inbox.map(String.init).joined(separator: ", "))
        ]

        for (key, value) in items {
            let line = "\(key): ".consoleText(palette.summaryKey) + value.consoleText(palette.summaryValue)
            terminal.output(line, newLine: true)
        }
    }

    private func renderGrid(state: ProgramState, highlight: Set<Int>) {
        for row in 0..<10 {
            let rowStart = row * 10
            var line: ConsoleText = "\(rowStart.zeroPadded) | ".consoleText(palette.rowLabel)
            for column in 0..<10 {
                let addressValue = rowStart + column
                let address = MailboxAddress(addressValue)
                let word = state.word(at: address).zeroPaddedString
                let isHighlight = highlight.contains(addressValue)
                let formatted = isHighlight ? "[\(word)]" : " \(word) "
                let style = isHighlight ? palette.gridHighlight : palette.gridValue
                line += formatted.consoleText(style)
                if column < 9 {
                    line += " ".consoleText()
                }
            }
            terminal.output(line, newLine: true)
        }
    }

    private func highlightSet(counter: MailboxAddress, extra: MailboxAddress?) -> Set<Int> {
        var result: Set<Int> = [counter.rawValue]
        if let extra {
            result.insert(extra.rawValue)
        }
        return result
    }
}

struct TerminalPalette {
    let header: ConsoleStyle
    let summaryKey: ConsoleStyle
    let summaryValue: ConsoleStyle
    let rowLabel: ConsoleStyle
    let gridValue: ConsoleStyle
    let gridHighlight: ConsoleStyle
    let label: ConsoleStyle
    let outboxValue: ConsoleStyle
    let traceHeader: ConsoleStyle
    let traceText: ConsoleStyle
    let eventHeader: ConsoleStyle
    let eventText: ConsoleStyle

    static let plain = TerminalPalette(header: .plain,
                                       summaryKey: .plain,
                                       summaryValue: .plain,
                                       rowLabel: .plain,
                                       gridValue: .plain,
                                       gridHighlight: .init(isBold: true),
                                       label: .plain,
                                       outboxValue: .plain,
                                       traceHeader: .plain,
                                       traceText: .plain,
                                       eventHeader: .plain,
                                       eventText: .plain)
}

extension TerminalThemeChoice {
    func palette(colored: Bool) -> TerminalPalette {
        guard colored else { return .plain }

        switch self {
        case .default:
            return TerminalPalette(header: .init(color: .brightCyan, isBold: true),
                                   summaryKey: .init(color: .brightBlack, isBold: true),
                                   summaryValue: .init(color: .brightWhite, isBold: true),
                                   rowLabel: .init(color: .brightBlack),
                                   gridValue: .init(color: .white),
                                   gridHighlight: .init(color: .brightWhite, background: .blue, isBold: true),
                                   label: .init(color: .brightMagenta),
                                   outboxValue: .init(color: .brightGreen, isBold: true),
                                   traceHeader: .init(color: .brightCyan, isBold: true),
                                   traceText: .init(color: .brightWhite),
                                   eventHeader: .init(color: .brightMagenta, isBold: true),
                                   eventText: .init(color: .brightWhite))
        case .monochrome:
            return TerminalPalette(header: .init(isBold: true),
                                   summaryKey: .init(isBold: true),
                                   summaryValue: .plain,
                                   rowLabel: .plain,
                                   gridValue: .plain,
                                   gridHighlight: .init(isBold: true),
                                   label: .init(isBold: true),
                                   outboxValue: .init(isBold: true),
                                   traceHeader: .init(isBold: true),
                                   traceText: .plain,
                                   eventHeader: .init(isBold: true),
                                   eventText: .plain)
        case .highContrast:
            return TerminalPalette(header: .init(color: .brightYellow, isBold: true),
                                   summaryKey: .init(color: .brightWhite, background: .blue, isBold: true),
                                   summaryValue: .init(color: .brightYellow, isBold: true),
                                   rowLabel: .init(color: .brightCyan, isBold: true),
                                   gridValue: .init(color: .brightWhite),
                                   gridHighlight: .init(color: .brightWhite, background: .brightMagenta, isBold: true),
                                   label: .init(color: .brightYellow, isBold: true),
                                   outboxValue: .init(color: .brightGreen, isBold: true),
                                   traceHeader: .init(color: .brightYellow, isBold: true),
                                   traceText: .init(color: .brightWhite),
                                   eventHeader: .init(color: .brightMagenta, isBold: true),
                                   eventText: .init(color: .brightWhite))
        }
    }
}

private extension Int {
    var zeroPadded: String {
        String(format: "%03d", self)
    }
}
