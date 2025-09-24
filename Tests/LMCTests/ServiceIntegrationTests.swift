#if canImport(Testing)
import CoreLittleManComputer
import Foundation
import Testing
@testable import LMC

@Test
func assemblyServiceCompilesInlineSource() async throws {
    let environment = try makeEnvironment()
    let service = AssemblyService(environment: environment)
    let response = try await service.assemble(.init(source: .inline("HLT"),
                                                    outputFormat: .json,
                                                    labelStyle: .symbolic))
    #expect(response.program.usedRange.count == 1)
    #expect(response.snapshot.words.first == 0)
    #expect(String(data: response.json, encoding: .utf8)?.contains("\"words\"" ) == true)
}

@Test
func snapshotServiceStoresAndListsSnapshots() async throws {
    let environment = try makeEnvironment()
    let assembly = AssemblyService(environment: environment)
    let snapshotService = SnapshotService(environment: environment)

    let response = try await assembly.assemble(.init(source: .inline("INP\nOUT\nHLT"),
                                                     outputFormat: .text,
                                                     labelStyle: .symbolic))
    let storeRequest = SnapshotService.StoreRequest(name: "adder",
                                                    snapshot: response.snapshot,
                                                    assembly: response.renderedAssembly)
    let url = try await snapshotService.store(storeRequest)
    #expect(FileManager.default.fileExists(atPath: url.path))

    let entries = try snapshotService.listSnapshots()
    #expect(entries.contains(where: { $0.name == "adder" }))
}

@Test
func executionServiceRunsProgramAndProducesOutbox() async throws {
    let environment = try makeEnvironment()
    let assembly = AssemblyService(environment: environment)
    let execution = ExecutionService(environment: environment)
    let assembleResponse = try await assembly.assemble(.init(source: .inline("INP\nOUT\nHLT"),
                                                             outputFormat: .json,
                                                             labelStyle: .symbolic))

    let outcome = try await execution.run(.init(source: .snapshot(assembleResponse.snapshot),
                                                inbox: [42],
                                                speed: nil,
                                                maxCycles: nil,
                                                breakpoints: [],
                                                plainOutput: true))
    #expect(outcome.state.outbox == [42])
    #expect(outcome.state.halted)
    #expect(outcome.breakpoint == nil)
}

@Test
func executionServiceResumesFromProvidedState() async throws {
    let environment = try makeEnvironment()
    let assembly = AssemblyService(environment: environment)
    let execution = ExecutionService(environment: environment)
    let response = try await assembly.assemble(.init(source: .inline("INP\nOUT\nHLT"),
                                                     outputFormat: .json,
                                                     labelStyle: .symbolic))

    let first = try await execution.run(.init(source: .snapshot(response.snapshot),
                                              inbox: [7],
                                              speed: nil,
                                              maxCycles: 1,
                                              breakpoints: [],
                                              plainOutput: true))
    #expect(first.state.halted == false)
    #expect(first.state.outbox.isEmpty)

    let second = try await execution.run(.init(source: .snapshot(response.snapshot),
                                               inbox: [],
                                               speed: nil,
                                               maxCycles: nil,
                                               breakpoints: [],
                                               plainOutput: true,
                                               initialState: first.state))
    #expect(second.state.halted)
    #expect(second.state.outbox == [7])
}

@Test
func snapshotServiceResolvesSnapshotsByName() async throws {
    let environment = try makeEnvironment()
    let assembly = AssemblyService(environment: environment)
    let snapshotService = SnapshotService(environment: environment)

    let response = try await assembly.assemble(.init(source: .inline("HLT"),
                                                     outputFormat: .json,
                                                     labelStyle: .symbolic))
    _ = try await snapshotService.store(.init(name: "halt",
                                              snapshot: response.snapshot,
                                              assembly: nil))

    let resolved = try snapshotService.resolveSnapshotURL(for: "halt")
    #expect(FileManager.default.fileExists(atPath: resolved.path))
}

@Test
func stateRendererHighlightsCounterAndMailbox() async throws {
    let assembler = Assembler()
    let program = try assembler.assemble("HLT")
    var state = ProgramState(counter: MailboxAddress(5))
    state.ensureMemoryInitialized(with: program.memoryImage)
    state.store(word: Word(321), at: MailboxAddress(5))

    let renderer = StateRenderer()
    let output = renderer.render(state: state,
                                 program: program,
                                 options: .init(highlightMailbox: MailboxAddress(5),
                                                showLabels: false,
                                                plainOutput: true))
    #expect(output.contains("Counter: 005"))
    #expect(output.contains("[321]"))
}

private func makeEnvironment() throws -> ServiceEnvironment {
    let temporary = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true)
    let options = try GlobalOptions.parse(["--workspace", temporary.path])
    return ServiceEnvironment(options: options)
}
#endif
