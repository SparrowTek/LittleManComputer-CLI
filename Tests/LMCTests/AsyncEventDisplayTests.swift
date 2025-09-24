import CoreLittleManComputer
import Foundation
import Testing
@testable import LMC

@Suite("Async Event Display Tests")
struct AsyncEventDisplayTests {

    @Test func testREPLEventObserverCapturesOutput() async throws {
        var capturedOutputs: [Int] = []
        var capturedBreakpoints: [MailboxAddress] = []

        let observer = REPLEventObserver(
            outputHandler: { value in
                capturedOutputs.append(value)
            },
            breakpointHandler: { address in
                capturedBreakpoints.append(address)
            }
        )

        // Simulate events
        observer.handle(.outputProduced(42))
        observer.handle(.outputProduced(100))
        observer.handle(.breakpointHit(MailboxAddress(10)))
        observer.handle(.cycleCompleted(cycle: 1, state: ProgramState())) // Should be ignored
        observer.handle(.outputProduced(200))

        #expect(capturedOutputs == [42, 100, 200])
        #expect(capturedBreakpoints.count == 1)
        #expect(capturedBreakpoints[0].rawValue == 10)
    }

    @Test func testREPLEventCollector() async throws {
        let collector = REPLEventCollector()

        // Record various events
        collector.recordOutput(10)
        collector.recordOutput(20)
        collector.recordBreakpoint(MailboxAddress(5))
        collector.recordOutput(30)
        collector.recordBreakpoint(MailboxAddress(15))
        collector.recordError("Test error")

        // Verify collections
        let outputs = collector.getOutputs()
        #expect(outputs == [10, 20, 30])

        let breakpoints = collector.getBreakpoints()
        #expect(breakpoints.count == 2)
        #expect(breakpoints[0].rawValue == 5)
        #expect(breakpoints[1].rawValue == 15)

        let errors = collector.getErrors()
        #expect(errors == ["Test error"])

        // Test clear
        collector.clear()
        #expect(collector.getOutputs().isEmpty)
        #expect(collector.getBreakpoints().isEmpty)
        #expect(collector.getErrors().isEmpty)
    }

    @Test func testEventObserverWithProgram() async throws {
        // Create a simple program that outputs values
        let source = """
        LDA num
        OUT
        HLT
        num DAT 42
        """

        let assembler = Assembler()
        let program = try assembler.assemble(source)

        // Set up observer
        var outputs: [Int] = []
        let observer = REPLEventObserver(
            outputHandler: { value in
                outputs.append(value)
            },
            breakpointHandler: { _ in }
        )

        // Create engine with observer
        let engine = ExecutionEngine(
            program: program,
            initialState: ProgramState(),
            observer: observer
        )

        // Run the program
        _ = try engine.runUntilHalt(maxCycles: 10)

        // Verify output was captured
        #expect(outputs == [42])
    }

    @Test func testEventObserverWithBreakpoints() async throws {
        // Create a program with multiple instructions
        let source = """
        INP
        OUT
        HLT
        """

        let assembler = Assembler()
        let program = try assembler.assemble(source)

        // Set up observer
        var breakpointHits: [MailboxAddress] = []
        let observer = REPLEventObserver(
            outputHandler: { _ in },
            breakpointHandler: { address in
                breakpointHits.append(address)
            }
        )

        // Create engine with observer and breakpoint
        let engine = ExecutionEngine(
            program: program,
            initialState: ProgramState(inbox: [100]),
            observer: observer
        )
        engine.addBreakpoint(MailboxAddress(1)) // Break at OUT instruction

        // Run the program
        do {
            _ = try engine.runUntilHalt(maxCycles: 10)
            #expect(Bool(false), "Should have hit breakpoint")
        } catch let error as ExecutionError {
            if case .breakpointHit(let addr) = error {
                #expect(addr.rawValue == 1)
            } else {
                throw error
            }
        }

        // Verify breakpoint was captured by observer
        #expect(breakpointHits.count == 1)
        #expect(breakpointHits[0].rawValue == 1)
    }

    @Test func testMultipleOutputEvents() async throws {
        // Create a program that outputs multiple values
        let source = """
        LDA val1
        OUT
        LDA val2
        OUT
        LDA val3
        OUT
        HLT
        val1 DAT 10
        val2 DAT 20
        val3 DAT 30
        """

        let assembler = Assembler()
        let program = try assembler.assemble(source)

        // Set up collector
        let collector = REPLEventCollector()
        let observer = REPLEventObserver(
            outputHandler: { value in
                collector.recordOutput(value)
            },
            breakpointHandler: { _ in }
        )

        // Create and run engine
        let engine = ExecutionEngine(
            program: program,
            initialState: ProgramState(),
            observer: observer
        )

        _ = try engine.runUntilHalt(maxCycles: 20)

        // Verify all outputs were captured
        let outputs = collector.getOutputs()
        #expect(outputs == [10, 20, 30])
    }
}