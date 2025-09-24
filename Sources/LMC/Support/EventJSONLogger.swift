import CoreLittleManComputer
import Foundation

final class EventJSONLogger: ExecutionObserver, @unchecked Sendable {
    private let handle: FileHandle
    private let encoder: JSONEncoder
    private let lock = NSLock()

    init(url: URL) throws {
        let fm = FileManager.default
        if fm.fileExists(atPath: url.path) {
            try fm.removeItem(at: url)
        }
        let directory = url.deletingLastPathComponent()
        if !directory.path.isEmpty && directory.path != "." {
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        guard fm.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        self.handle = try FileHandle(forWritingTo: url)
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
    }

    func handle(_ event: ExecutionEvent) {
        let line = EventLogLine(timestamp: Date(), kind: event.kind, data: EventPayload(event: event))
        write(line)
    }

    func log(state: ProgramState) {
        let snapshot = state.snapshot()
        let line = StateLogLine(timestamp: Date(), snapshot: snapshot)
        write(line)
    }

    func close() {
        lock.lock()
        defer { lock.unlock() }
        try? handle.synchronize()
        try? handle.close()
    }

    private func write<T: Encodable>(_ value: T) {
        do {
            let data = try encoder.encode(value)
            lock.lock()
            handle.write(data)
            handle.write(Data([0x0A]))
            lock.unlock()
        } catch {
            // swallow logging errors
        }
    }

    private struct EventLogLine: Encodable {
        let category = "event"
        let timestamp: Date
        let kind: String
        let data: EventPayload
    }

    private struct StateLogLine: Encodable {
        let category = "state"
        let timestamp: Date
        let snapshot: ProgramStateSnapshot
    }

    private struct EventPayload: Encodable {
        let cycle: Int?
        let counter: Int?
        let opcode: String?
        let accumulator: Int?
        let value: Int?
        let message: String?

        init(event: ExecutionEvent) {
            switch event {
            case .cycleStarted(let cycle, let counter):
                self.cycle = cycle
                self.counter = counter.rawValue
                self.opcode = nil
                self.accumulator = nil
                self.value = nil
                self.message = nil
            case .instructionDecoded(let instruction):
                self.cycle = nil
                self.counter = nil
                self.opcode = instruction.opcode.metadata.mnemonic
                self.accumulator = nil
                self.value = nil
                self.message = nil
            case .instructionExecuted(let instruction, let state):
                self.cycle = state.cycles
                self.counter = state.counter.rawValue
                self.opcode = instruction.opcode.metadata.mnemonic
                self.accumulator = state.accumulator.value
                self.value = nil
                self.message = nil
            case .cycleCompleted(let cycle, let state):
                self.cycle = cycle
                self.counter = state.counter.rawValue
                self.opcode = nil
                self.accumulator = state.accumulator.value
                self.value = nil
                self.message = nil
            case .inputRequested:
                self.cycle = nil
                self.counter = nil
                self.opcode = nil
                self.accumulator = nil
                self.value = nil
                self.message = "inputRequested"
            case .outputProduced(let produced):
                self.cycle = nil
                self.counter = nil
                self.opcode = nil
                self.accumulator = nil
                self.value = produced
                self.message = nil
            case .breakpointHit(let address):
                self.cycle = nil
                self.counter = address.rawValue
                self.opcode = nil
                self.accumulator = nil
                self.value = nil
                self.message = "breakpoint"
            case .halted:
                self.cycle = nil
                self.counter = nil
                self.opcode = nil
                self.accumulator = nil
                self.value = nil
                self.message = "halted"
            case .error(let errorMessage):
                self.cycle = nil
                self.counter = nil
                self.opcode = nil
                self.accumulator = nil
                self.value = nil
                self.message = errorMessage
            }
        }

        private enum CodingKeys: String, CodingKey {
            case cycle
            case counter
            case opcode
            case accumulator
            case value
            case message
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            if let cycle {
                try container.encode(cycle, forKey: .cycle)
            }
            if let counter {
                try container.encode(counter, forKey: .counter)
            }
            if let opcode {
                try container.encode(opcode, forKey: .opcode)
            }
            if let accumulator {
                try container.encode(accumulator, forKey: .accumulator)
            }
            if let value {
                try container.encode(value, forKey: .value)
            }
            if let message {
                try container.encode(message, forKey: .message)
            }
        }
    }
}

private extension ExecutionEvent {
    var kind: String {
        switch self {
        case .cycleStarted:
            return "cycleStarted"
        case .instructionDecoded:
            return "instructionDecoded"
        case .instructionExecuted:
            return "instructionExecuted"
        case .cycleCompleted:
            return "cycleCompleted"
        case .inputRequested:
            return "inputRequested"
        case .outputProduced:
            return "outputProduced"
        case .breakpointHit:
            return "breakpointHit"
        case .halted:
            return "halted"
        case .error:
            return "error"
        }
    }
}
