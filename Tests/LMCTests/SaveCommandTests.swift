#if canImport(Testing)
import CoreLittleManComputer
import Foundation
import Testing
@testable import LMC

struct SaveCommandTests {
    @Test
    func snapshotServiceStoresProgram() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)
        let snapshotService = SnapshotService(environment: environment)

        // Create a test program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )

        // Save the program
        let storeRequest = SnapshotService.StoreRequest(
            name: "test-program",
            snapshot: response.snapshot,
            assembly: nil
        )
        let url = try await snapshotService.store(storeRequest)

        // Verify file exists
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.lastPathComponent == "test-program.json")

        // Verify can be loaded back
        let data = try Data(contentsOf: url)
        let loadedSnapshot = try JSONDecoder().decode(ProgramSnapshot.self, from: data)
        #expect(loadedSnapshot.words == response.snapshot.words)
    }

    @Test
    func snapshotServiceStoresState() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)
        let snapshotService = SnapshotService(environment: environment)
        let executionService = ExecutionService(environment: environment)

        // Create a test program and run it partially
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )

        // Run the program with some input to generate state
        let outcome = try await executionService.run(.init(
            source: .snapshot(response.snapshot),
            inbox: [42],
            maxCycles: 1  // Run just one cycle
        ))

        // Save the state with program
        let stateSnapshot = ProgramStateSnapshot(state: outcome.state)
        let stateRequest = SnapshotService.StoreStateRequest(
            name: "test-state",
            stateSnapshot: stateSnapshot,
            programSnapshot: response.snapshot
        )
        let url = try await snapshotService.storeState(stateRequest)

        // Verify file exists
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(url.lastPathComponent == "test-state.json")

        // Verify can be loaded back
        let data = try Data(contentsOf: url)
        let decoder = JSONDecoder()

        // The saved format is a CombinedSnapshot
        struct CombinedSnapshot: Codable {
            let state: ProgramStateSnapshot
            let program: ProgramSnapshot?
        }

        let loaded = try decoder.decode(CombinedSnapshot.self, from: data)
        #expect(loaded.state.counter == 1)
        #expect(loaded.state.accumulator == 42)
        #expect(loaded.state.cycles == 1)
        #expect(loaded.program != nil)
    }

    @Test
    func nameValidationRejectsInvalidNames() async throws {
        let environment = try makeEnvironment()
        let snapshotService = SnapshotService(environment: environment)

        // Test that invalid names are rejected when trying to store
        let assemblyService = AssemblyService(environment: environment)
        let response = try await assemblyService.assemble(
            .init(source: .inline("HLT"), outputFormat: .json, labelStyle: .symbolic)
        )

        // Test invalid name with slash
        let invalidRequest1 = SnapshotService.StoreRequest(
            name: "test/program",
            snapshot: response.snapshot,
            assembly: nil
        )
        await #expect(throws: SnapshotService.Error.self) {
            _ = try await snapshotService.store(invalidRequest1)
        }

        // Test invalid name with space
        let invalidRequest2 = SnapshotService.StoreRequest(
            name: "test program",
            snapshot: response.snapshot,
            assembly: nil
        )
        await #expect(throws: SnapshotService.Error.self) {
            _ = try await snapshotService.store(invalidRequest2)
        }

        // Test empty name
        let invalidRequest3 = SnapshotService.StoreRequest(
            name: "",
            snapshot: response.snapshot,
            assembly: nil
        )
        await #expect(throws: SnapshotService.Error.self) {
            _ = try await snapshotService.store(invalidRequest3)
        }
    }

    @Test
    func stateSnapshotIncludesMemory() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)
        let executionService = ExecutionService(environment: environment)

        // Create a program with data values
        let response = try await assemblyService.assemble(
            .init(source: .inline("LDA 4\nHLT\nDAT 0\nDAT 0\nDAT 42"), outputFormat: .json, labelStyle: .symbolic)
        )

        // Run one cycle to load value into accumulator
        let outcome = try await executionService.run(.init(
            source: .snapshot(response.snapshot),
            inbox: [],
            maxCycles: 1
        ))

        // Create state snapshot
        let stateSnapshot = ProgramStateSnapshot(state: outcome.state)

        // Verify the state snapshot captures memory correctly
        #expect(stateSnapshot.accumulator == 42)
        #expect(stateSnapshot.counter == 1)
        #expect(stateSnapshot.memory.count == 100)
    }
}

private func makeEnvironment() throws -> ServiceEnvironment {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lmc-save-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let options = try GlobalOptions.parse(["--workspace", tempDir.path])
    return ServiceEnvironment(options: options)
}

#endif