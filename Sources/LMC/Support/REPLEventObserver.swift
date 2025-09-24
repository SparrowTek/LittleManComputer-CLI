import CoreLittleManComputer
import Foundation

/// An execution observer that displays certain events immediately during REPL execution
final class REPLEventObserver: ExecutionObserver, @unchecked Sendable {
    private let outputHandler: (Int) -> Void
    private let breakpointHandler: (MailboxAddress) -> Void
    private let inputHandler: () -> Void
    private let errorHandler: (String) -> Void

    init(
        outputHandler: @escaping (Int) -> Void,
        breakpointHandler: @escaping (MailboxAddress) -> Void,
        inputHandler: @escaping () -> Void = {},
        errorHandler: @escaping (String) -> Void = { _ in }
    ) {
        self.outputHandler = outputHandler
        self.breakpointHandler = breakpointHandler
        self.inputHandler = inputHandler
        self.errorHandler = errorHandler
    }

    func handle(_ event: ExecutionEvent) {
        switch event {
        case .outputProduced(let value):
            outputHandler(value)
        case .breakpointHit(let address):
            breakpointHandler(address)
        case .inputRequested:
            inputHandler()
        case .error(let message):
            errorHandler(message)
        default:
            // Ignore other events for real-time display
            break
        }
    }
}

/// A container for collecting events during REPL execution
final class REPLEventCollector: @unchecked Sendable {
    private var outputs: [Int] = []
    private var breakpoints: [MailboxAddress] = []
    private var errors: [String] = []
    private let lock = NSLock()

    func recordOutput(_ value: Int) {
        lock.lock()
        outputs.append(value)
        lock.unlock()
    }

    func recordBreakpoint(_ address: MailboxAddress) {
        lock.lock()
        breakpoints.append(address)
        lock.unlock()
    }

    func recordError(_ message: String) {
        lock.lock()
        errors.append(message)
        lock.unlock()
    }

    func getOutputs() -> [Int] {
        lock.lock()
        defer { lock.unlock() }
        return outputs
    }

    func getBreakpoints() -> [MailboxAddress] {
        lock.lock()
        defer { lock.unlock() }
        return breakpoints
    }

    func getErrors() -> [String] {
        lock.lock()
        defer { lock.unlock() }
        return errors
    }

    func clear() {
        lock.lock()
        outputs.removeAll()
        breakpoints.removeAll()
        errors.removeAll()
        lock.unlock()
    }
}