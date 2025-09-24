#if canImport(Testing)
import CoreLittleManComputer
import Foundation
import Testing
@testable import LMC

struct ImportExportTests {
    @Test
    func exportProgramOnly() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)
        let snapshotService = SnapshotService(environment: environment)

        // Create and store a test program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let storeRequest = SnapshotService.StoreRequest(
            name: "test-export",
            snapshot: response.snapshot,
            assembly: "INP\nOUT\nHLT"
        )
        _ = try await snapshotService.store(storeRequest)

        // Export the program
        let exportData = try await snapshotService.exportProgram(
            name: "test-export",
            includeState: false,
            description: "Test export"
        )

        // Decode and verify the export bundle
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(SnapshotService.ExportBundle.self, from: exportData)

        #expect(bundle.version == SnapshotService.ExportBundle.currentVersion)
        #expect(bundle.metadata.originalName == "test-export")
        #expect(bundle.metadata.description == "Test export")
        #expect(bundle.program.words == response.snapshot.words)
        #expect(bundle.assembly == "INP\nOUT\nHLT")
        #expect(bundle.state == nil)
    }

    @Test
    func exportProgramWithState() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)
        let snapshotService = SnapshotService(environment: environment)
        let executionService = ExecutionService(environment: environment)

        // Create a test program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )

        // Store the program
        let storeRequest = SnapshotService.StoreRequest(
            name: "test-with-state",
            snapshot: response.snapshot,
            assembly: nil
        )
        _ = try await snapshotService.store(storeRequest)

        // Run the program partially to generate state
        let outcome = try await executionService.run(.init(
            source: .snapshot(response.snapshot),
            inbox: [42],
            maxCycles: 1
        ))

        // Store the state
        let stateSnapshot = ProgramStateSnapshot(state: outcome.state)
        let stateRequest = SnapshotService.StoreStateRequest(
            name: "test-with-state-state",
            stateSnapshot: stateSnapshot,
            programSnapshot: response.snapshot
        )
        _ = try await snapshotService.storeState(stateRequest)

        // Export with state
        let exportData = try await snapshotService.exportProgram(
            name: "test-with-state",
            includeState: true,
            description: nil
        )

        // Verify the export includes state
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(SnapshotService.ExportBundle.self, from: exportData)

        #expect(bundle.state != nil)
        #expect(bundle.state?.counter == 1)
        #expect(bundle.state?.accumulator == 42)
    }

    @Test
    func exportIncludesBreakpoints() async throws {
        let environment = try makeEnvironment()
        let assemblyService = AssemblyService(environment: environment)
        let snapshotService = SnapshotService(environment: environment)
        let breakpointStore = BreakpointStore(environment: environment)

        // Create and store a program
        let response = try await assemblyService.assemble(
            .init(source: .inline("INP\nOUT\nHLT"), outputFormat: .json, labelStyle: .symbolic)
        )
        let storeRequest = SnapshotService.StoreRequest(
            name: "test-with-breakpoints",
            snapshot: response.snapshot,
            assembly: nil
        )
        _ = try await snapshotService.store(storeRequest)

        // Add breakpoints
        let program = response.program
        try breakpointStore.addBreakpoints([1, 2], to: program)

        // Export the program
        let exportData = try await snapshotService.exportProgram(
            name: "test-with-breakpoints",
            includeState: false,
            description: nil
        )

        // Verify breakpoints are included
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let bundle = try decoder.decode(SnapshotService.ExportBundle.self, from: exportData)

        #expect(bundle.breakpoints == [1, 2])
    }

    @Test
    func importProgramBundle() async throws {
        let environment = try makeEnvironment()
        let snapshotService = SnapshotService(environment: environment)

        // Create a test bundle
        let programSnapshot = ProgramSnapshot(
            version: ProgramSnapshot.currentVersion,
            metadata: SnapshotMetadata(schemaVersion: ProgramSnapshot.currentVersion),
            words: [901, 902, 0],
            usedCount: 3,
            labels: [:]
        )

        let bundle = SnapshotService.ExportBundle(
            version: SnapshotService.ExportBundle.currentVersion,
            metadata: SnapshotService.ExportMetadata(
                originalName: "imported-program",
                description: "Test import"
            ),
            program: programSnapshot,
            state: nil,
            assembly: "INP\nOUT\nHLT",
            breakpoints: [1, 2]
        )

        // Encode the bundle
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bundleData = try encoder.encode(bundle)

        // Import the bundle
        let (programURL, stateURL) = try await snapshotService.importProgram(
            from: bundleData,
            as: nil  // Use original name
        )

        // Verify the program was imported
        #expect(FileManager.default.fileExists(atPath: programURL.path))
        #expect(programURL.lastPathComponent == "imported-program.json")
        #expect(stateURL == nil)

        // Verify assembly was saved
        let assemblyURL = programURL.deletingPathExtension().appendingPathExtension("lmc")
        #expect(FileManager.default.fileExists(atPath: assemblyURL.path))

        // Verify breakpoints were restored
        let breakpointStore = BreakpointStore(environment: environment)
        let decoder = JSONDecoder()
        let programData = try Data(contentsOf: programURL)
        let loadedSnapshot = try decoder.decode(ProgramSnapshot.self, from: programData)
        let loadedProgram = try Program(snapshot: loadedSnapshot)
        let breakpoints = breakpointStore.getBreakpoints(for: loadedProgram)
        #expect(breakpoints.map { $0.rawValue } == [1, 2])
    }

    @Test
    func importWithRename() async throws {
        let environment = try makeEnvironment()
        let snapshotService = SnapshotService(environment: environment)

        // Create a test bundle
        let programSnapshot = ProgramSnapshot(
            version: ProgramSnapshot.currentVersion,
            metadata: SnapshotMetadata(schemaVersion: ProgramSnapshot.currentVersion),
            words: [0],
            usedCount: 1,
            labels: [:]
        )

        let bundle = SnapshotService.ExportBundle(
            version: SnapshotService.ExportBundle.currentVersion,
            metadata: SnapshotService.ExportMetadata(originalName: "original-name"),
            program: programSnapshot,
            state: nil,
            assembly: nil,
            breakpoints: nil
        )

        // Encode the bundle
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let bundleData = try encoder.encode(bundle)

        // Import with a different name
        let (programURL, _) = try await snapshotService.importProgram(
            from: bundleData,
            as: "new-name"
        )

        // Verify the program was imported with the new name
        #expect(programURL.lastPathComponent == "new-name.json")
    }

    @Test
    func importVersionValidation() async throws {
        let environment = try makeEnvironment()
        let snapshotService = SnapshotService(environment: environment)

        // Create a bundle with a future version
        let programSnapshot = ProgramSnapshot(
            version: ProgramSnapshot.currentVersion,
            metadata: SnapshotMetadata(schemaVersion: ProgramSnapshot.currentVersion),
            words: [0],
            usedCount: 1,
            labels: [:]
        )

        let bundle = SnapshotService.ExportBundle(
            version: 999,  // Future version
            metadata: SnapshotService.ExportMetadata(originalName: "test"),
            program: programSnapshot,
            state: nil,
            assembly: nil,
            breakpoints: nil
        )

        // Encode the bundle
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601  // Match the export encoder
        let bundleData = try encoder.encode(bundle)

        // Import should fail with version error
        await #expect(throws: SnapshotService.Error.self) {
            _ = try await snapshotService.importProgram(from: bundleData)
        }
    }

    @Test
    func roundTripExportImport() async throws {
        let environment1 = try makeEnvironment()
        let environment2 = try makeEnvironment()  // Simulating a different system

        let assemblyService = AssemblyService(environment: environment1)
        let snapshotService1 = SnapshotService(environment: environment1)
        let snapshotService2 = SnapshotService(environment: environment2)
        let executionService = ExecutionService(environment: environment1)

        // Create a complex program in environment1
        let response = try await assemblyService.assemble(
            .init(source: .inline("LDA 5\nADD 6\nOUT\nHLT\nDAT 0\nDAT 10\nDAT 20"),
                 outputFormat: .json,
                 labelStyle: .symbolic)
        )

        // Store it
        _ = try await snapshotService1.store(SnapshotService.StoreRequest(
            name: "complex-program",
            snapshot: response.snapshot,
            assembly: "LDA 5\nADD 6\nOUT\nHLT\nDAT 0\nDAT 10\nDAT 20"
        ))

        // Run it to generate state
        let outcome = try await executionService.run(.init(
            source: .snapshot(response.snapshot),
            inbox: [],
            maxCycles: 2
        ))

        // Store state
        _ = try await snapshotService1.storeState(SnapshotService.StoreStateRequest(
            name: "complex-program-state",
            stateSnapshot: ProgramStateSnapshot(state: outcome.state),
            programSnapshot: response.snapshot
        ))

        // Add breakpoints
        let breakpointStore1 = BreakpointStore(environment: environment1)
        try breakpointStore1.addBreakpoints([2, 3], to: response.program)

        // Export from environment1
        let exportData = try await snapshotService1.exportProgram(
            name: "complex-program",
            includeState: true,
            description: "Round trip test"
        )

        // Import into environment2
        let (importedProgramURL, importedStateURL) = try await snapshotService2.importProgram(
            from: exportData,
            as: "imported-complex"
        )

        // Verify everything was preserved
        #expect(FileManager.default.fileExists(atPath: importedProgramURL.path))
        #expect(importedStateURL != nil)

        // Load and verify program
        let importedProgramData = try Data(contentsOf: importedProgramURL)
        let decoder = JSONDecoder()
        let importedSnapshot = try decoder.decode(ProgramSnapshot.self, from: importedProgramData)
        #expect(importedSnapshot.words == response.snapshot.words)

        // Verify breakpoints
        let breakpointStore2 = BreakpointStore(environment: environment2)
        let importedProgram = try Program(snapshot: importedSnapshot)
        let importedBreakpoints = breakpointStore2.getBreakpoints(for: importedProgram)
        #expect(importedBreakpoints.map { $0.rawValue } == [2, 3])
    }
}

private func makeEnvironment() throws -> ServiceEnvironment {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent("lmc-import-export-test-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

    let options = try GlobalOptions.parse(["--workspace", tempDir.path])
    return ServiceEnvironment(options: options)
}

#endif