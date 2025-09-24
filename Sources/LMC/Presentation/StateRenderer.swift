import CoreLittleManComputer
import Foundation

struct StateRenderer {
    struct Options {
        var highlightMailbox: MailboxAddress?
        var showLabels: Bool
        var plainOutput: Bool
        var compact: Bool

        init(highlightMailbox: MailboxAddress? = nil,
             showLabels: Bool = true,
             plainOutput: Bool = false,
             compact: Bool = false) {
            self.highlightMailbox = highlightMailbox
            self.showLabels = showLabels
            self.plainOutput = plainOutput
            self.compact = compact
        }
    }

    func render(state: ProgramState, program: Program?, options: Options) -> String {
        var lines: [String] = []
        lines.append(summary(for: state))
        if !options.compact {
            lines.append("")
            lines.append("Memory")
            lines.append(renderGrid(for: state, highlight: highlightSet(counter: state.counter,
                                                                          extra: options.highlightMailbox)))

            if options.showLabels, let program, !program.labels.isEmpty {
                lines.append("")
                lines.append("Labels")
                let sorted = program.labels.sorted { $0.key.lowercased() < $1.key.lowercased() }
                for (label, address) in sorted {
                    lines.append("  \(label): \(address.rawValue.zeroPadded)")
                }
            }
        }

        if !state.outbox.isEmpty {
            lines.append("")
            lines.append("Outbox")
            lines.append("  \(state.outbox.map(String.init).joined(separator: ", "))")
        }

        return lines.joined(separator: "\n")
    }

    private func summary(for state: ProgramState) -> String {
        [
            "Counter: \(state.counter.rawValue.zeroPadded)",
            "Accumulator: \(state.accumulator.value)",
            "Halted: \(state.halted)",
            "Cycles: \(state.cycles)",
            "Inbox: \(state.inbox.map(String.init).joined(separator: ", "))"
        ].joined(separator: "\n")
    }

    private func renderGrid(for state: ProgramState, highlight: Set<Int>) -> String {
        var rows: [String] = []
        for row in 0..<10 {
            var columns: [String] = []
            for column in 0..<10 {
                let address = row * 10 + column
                let word = state.word(at: MailboxAddress(address))
                let value = word.zeroPaddedString
                if highlight.contains(address) {
                    columns.append("[\(value)]")
                } else {
                    columns.append(" \(value) ")
                }
            }
            let rowLabel = "\((row * 10).zeroPadded)" // row start address
            rows.append("\(rowLabel) | \(columns.joined(separator: " "))")
        }
        return rows.joined(separator: "\n")
    }

    private func highlightSet(counter: MailboxAddress, extra: MailboxAddress?) -> Set<Int> {
        var result: Set<Int> = [counter.rawValue]
        if let extra {
            result.insert(extra.rawValue)
        }
        return result
    }
}

private extension Int {
    var zeroPadded: String {
        String(format: "%03d", self)
    }
}
