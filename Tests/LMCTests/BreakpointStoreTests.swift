#if canImport(Testing)
import CoreLittleManComputer
import Foundation
import Testing
@testable import LMC

struct BreakpointStoreTests {
    @Test
    func addAndRetrieveBreakpoints() async throws {
        let environment = try makeEnvironment()
        let breakpointStore = BreakpointStore(environment: environment)
        let assemblyService = AssemblyService(environment: environment)

        // Create a test program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program = response.program

        // Add breakpoints
        try breakpointStore.addBreakpoints([10, 20, 30], to: program, name: "TestProgram")

        // Retrieve breakpoints
        let breakpoints = breakpointStore.getBreakpoints(for: program)
        #expect(breakpoints.count == 3)
        #expect(breakpoints.map { $0.rawValue }.sorted() == [10, 20, 30])
    }

    @Test
    func removeBreakpoints() async throws {
        let environment = try makeEnvironment()
        let breakpointStore = BreakpointStore(environment: environment)
        let assemblyService = AssemblyService(environment: environment)

        // Create a test program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program = response.program

        // Add breakpoints
        try breakpointStore.addBreakpoints([10, 20, 30, 40], to: program)

        // Remove some breakpoints
        try breakpointStore.removeBreakpoints([20, 30], from: program)

        // Check remaining breakpoints
        let remaining = breakpointStore.getBreakpoints(for: program)
        #expect(remaining.count == 2)
        #expect(remaining.map { $0.rawValue }.sorted() == [10, 40])
    }

    @Test
    func clearAllBreakpoints() async throws {
        let environment = try makeEnvironment()
        let breakpointStore = BreakpointStore(environment: environment)
        let assemblyService = AssemblyService(environment: environment)

        // Create a test program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program = response.program

        // Add breakpoints
        try breakpointStore.addBreakpoints([10, 20, 30], to: program)

        // Clear all breakpoints
        try breakpointStore.clearBreakpoints(for: program)

        // Check no breakpoints remain
        let remaining = breakpointStore.getBreakpoints(for: program)
        #expect(remaining.isEmpty)
    }

    @Test
    func persistenceAcrossSessions() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)

        // Create a test program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program = response.program

        // First session: add breakpoints
        do {
            let breakpointStore = BreakpointStore(environment: environment)
            try breakpointStore.addBreakpoints([15, 25, 35], to: program, name: "PersistentProgram")
        }

        // Second session: retrieve breakpoints
        do {
            let breakpointStore = BreakpointStore(environment: environment)
            let breakpoints = breakpointStore.getBreakpoints(for: program)
            #expect(breakpoints.count == 3)
            #expect(breakpoints.map { $0.rawValue }.sorted() == [15, 25, 35])
        }
    }

    @Test
    func listAllBreakpoints() async throws {
        let environment = try makeEnvironment()
        let breakpointStore = BreakpointStore(environment: environment)
        let assemblyService = AssemblyService(environment: environment)

        // Create two different programs
        let response1 = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program1 = response1.program

        let response2 = try await assemblyService.assemble(
            .init(source: .inline("LDA 10\nADD 20\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program2 = response2.program

        // Add breakpoints to both programs
        try breakpointStore.addBreakpoints([10, 20], to: program1, name: "Program1")
        try breakpointStore.addBreakpoints([30, 40], to: program2, name: "Program2")

        // List all breakpoints
        let allBreakpoints = try breakpointStore.listAllBreakpoints()
        #expect(allBreakpoints.count == 2)

        // Check that both programs have their breakpoints
        let prog1Hash = breakpointStore.computeProgramHash(program1)
        let prog2Hash = breakpointStore.computeProgramHash(program2)

        let prog1Entry = allBreakpoints.first { $0.programHash == prog1Hash }
        let prog2Entry = allBreakpoints.first { $0.programHash == prog2Hash }

        #expect(prog1Entry != nil)
        #expect(prog1Entry?.programName == "Program1")
        #expect(prog1Entry?.breakpoints.map { $0.rawValue }.sorted() == [10, 20])

        #expect(prog2Entry != nil)
        #expect(prog2Entry?.programName == "Program2")
        #expect(prog2Entry?.breakpoints.map { $0.rawValue }.sorted() == [30, 40])
    }

    @Test
    func invalidAddressValidation() async throws {
        let environment = try makeEnvironment()
        let breakpointStore = BreakpointStore(environment: environment)
        let assemblyService = AssemblyService(environment: environment)

        // Create a test program
        let response = try await assemblyService.assemble(
            .init(source: .inline("HLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program = response.program

        // Try to add invalid addresses
        #expect(throws: BreakpointStore.Error.self) {
            try breakpointStore.addBreakpoints([100], to: program)
        }

        #expect(throws: BreakpointStore.Error.self) {
            try breakpointStore.addBreakpoints([-1], to: program)
        }
    }

    @Test
    func programHashConsistency() async throws {
        let environment = try makeEnvironment()
        let breakpointStore = BreakpointStore(environment: environment)
        let assemblyService = AssemblyService(environment: environment)

        // Create a program and compute its hash
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program = response.program
        let snapshot = response.snapshot

        // Hash should be consistent between program and snapshot
        let programHash = breakpointStore.computeProgramHash(program)
        let snapshotHash = breakpointStore.computeProgramHash(snapshot)
        #expect(programHash == snapshotHash)
    }

    @Test
    func autoLoadBreakpointsInExecution() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)
        let executionService = ExecutionService(environment: environment)
        let breakpointStore = BreakpointStore(environment: environment)

        // Create a program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nADD 10\nOUT\nHLT\nDAT 5"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program = response.program

        // Add persistent breakpoints
        try breakpointStore.addBreakpoints([1, 2], to: program, name: "TestProgram")

        // Run the program with auto-load enabled
        let outcome = try await executionService.run(.init(
            source: .snapshot(response.snapshot),
            inbox: [10],
            autoLoadBreakpoints: true
        ))

        // The program should hit the breakpoint at address 1
        #expect(outcome.breakpoint != nil)
        #expect(outcome.breakpoint?.rawValue == 1)
    }

    @Test
    func disableAutoLoadBreakpoints() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)
        let executionService = ExecutionService(environment: environment)
        let breakpointStore = BreakpointStore(environment: environment)

        // Create a program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let program = response.program

        // Add persistent breakpoints
        try breakpointStore.addBreakpoints([1], to: program)

        // Run with auto-load disabled
        let outcome = try await executionService.run(.init(
            source: .snapshot(response.snapshot),
            inbox: [10],
            autoLoadBreakpoints: false
        ))

        // Should not hit the breakpoint
        #expect(outcome.breakpoint == nil)
        #expect(outcome.state.halted)
    }
}

private func makeEnvironment() throws -> ServiceEnvironment {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lmc-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let options = try GlobalOptions.parse(["--workspace", tempDir.path])
    return ServiceEnvironment(options: options)
}

#endif