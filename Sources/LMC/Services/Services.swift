@preconcurrency import ArgumentParser
import CoreLittleManComputer
import Foundation
import CryptoKit

struct ServiceRegistry {
    let assembly: AssemblyService
    let execution: ExecutionService
    let snapshot: SnapshotService
    let breakpoints: BreakpointStore

    init(environment: ServiceEnvironment) {
        self.assembly = AssemblyService(environment: environment)
        self.execution = ExecutionService(environment: environment)
        self.snapshot = SnapshotService(environment: environment)
        self.breakpoints = BreakpointStore(environment: environment)
    }
}

private extension Int {
    var zeroPadded: String {
        String(format: "%03d", self)
    }
}

enum ServiceError: Error {
    case unimplemented(feature: StaticString)
}

struct AssemblyService {
    enum Error: Swift.Error, CustomStringConvertible {
        case emptyInput
        case unreadableSource(String)
        case encodingFailure(Swift.Error)
        case assemblyFailure(String)
        case snapshotUnreadable(String)

        var description: String {
            switch self {
            case .emptyInput:
                return "No source code provided. Provide a file path or pipe source via stdin."
            case .unreadableSource(let path):
                return "Unable to read source from \(path)."
            case .encodingFailure(let error):
                return "Failed to encode snapshot: \(error)"
            case .assemblyFailure(let message):
                return message
            case .snapshotUnreadable(let message):
                return message
            }
        }
    }

    struct Request {
        enum Source {
            case stdin
            case file(URL)
            case inline(String)
        }

        var source: Source
        var outputFormat: OutputFormat
        var labelStyle: LabelStyle

        init(source: Source,
             outputFormat: OutputFormat = .json,
             labelStyle: LabelStyle = .symbolic) {
            self.source = source
            self.outputFormat = outputFormat
            self.labelStyle = labelStyle
        }
    }

    struct Response {
        let program: Program
        let snapshot: ProgramSnapshot
        let json: Data
        let renderedAssembly: String?
    }

    struct DisassemblyRequest {
        var snapshotURL: URL
        var annotate: Bool
    }

    struct DisassemblyResponse {
        let assembly: String
        let metadata: SnapshotMetadata
    }

    enum OutputFormat: String, ExpressibleByArgument {
        case json
        case text
    }

    enum LabelStyle: String, ExpressibleByArgument {
        case numeric
        case symbolic
    }

    let environment: ServiceEnvironment
    private let codec: ProgramTextCodec
    private let serializer: ProgramSerializer

    init(environment: ServiceEnvironment) {
        self.environment = environment
        self.codec = ProgramTextCodec()
        self.serializer = ProgramSerializer(prettyPrinted: true)
    }

    func assemble(_ request: Request) async throws -> Response {
        let source = try readSource(request.source)
        guard source.contains(where: { !$0.isWhitespace && !$0.isNewline }) else {
            throw Error.emptyInput
        }

        let program: Program
        do {
            program = try codec.assemble(source)
        } catch let error as AssemblerError {
            throw Error.assemblyFailure(describeAssemblerError(error))
        } catch {
            throw Error.assemblyFailure(error.localizedDescription)
        }
        let snapshot = program.snapshot()
        let jsonData: Data
        do {
            jsonData = try serializer.exportJSON(program)
        } catch {
            throw Error.encodingFailure(error)
        }

        let rendered: String?
        switch request.outputFormat {
        case .json:
            rendered = nil
        case .text:
            rendered = renderAssembly(program, style: request.labelStyle)
        }

        return Response(program: program,
                        snapshot: snapshot,
                        json: jsonData,
                        renderedAssembly: rendered)
    }

    func disassemble(_ request: DisassemblyRequest) async throws -> DisassemblyResponse {
        let data: Data
        do {
            data = try Data(contentsOf: request.snapshotURL)
        } catch {
            throw Error.snapshotUnreadable("Unable to read snapshot at \(request.snapshotURL.path): \(error.localizedDescription)")
        }

        let decoder = JSONDecoder()
        let snapshot: ProgramSnapshot
        do {
            snapshot = try decoder.decode(ProgramSnapshot.self, from: data)
        } catch let error as DecodingError {
            throw Error.snapshotUnreadable("Snapshot decode failed: \(error.localizedDescription)")
        } catch {
            throw Error.snapshotUnreadable(error.localizedDescription)
        }

        let program: Program
        do {
            program = try Program(snapshot: snapshot)
        } catch {
            throw Error.snapshotUnreadable("Snapshot is invalid: \(error)")
        }
        let assembly = renderAssembly(program, style: .symbolic)
        let annotated: String
        if request.annotate {
            annotated = annotation(for: snapshot, source: assembly)
        } else {
            annotated = assembly
        }
        return DisassemblyResponse(assembly: annotated, metadata: snapshot.metadata)
    }

    private func readSource(_ source: Request.Source) throws -> String {
        switch source {
        case .stdin:
            let data = FileHandle.standardInput.readDataToEndOfFile()
            guard let text = String(data: data, encoding: .utf8) else {
                throw Error.emptyInput
            }
            return text
        case .file(let url):
            do {
                return try String(contentsOf: url)
            } catch {
                throw Error.unreadableSource(url.path)
            }
        case .inline(let text):
            return text
        }
    }

    private func renderAssembly(_ program: Program, style: LabelStyle) -> String {
        let disassembled = codec.disassemble(program)
        switch style {
        case .symbolic:
            return disassembled
        case .numeric:
            let lines = disassembled.split(separator: "\n", omittingEmptySubsequences: false)
            let start = program.usedRange.lowerBound
            return lines.enumerated().map { offset, line in
                let address = start + offset
                return "\(address.zeroPadded) \(line)"
            }.joined(separator: "\n")
        }
    }

    private func annotation(for snapshot: ProgramSnapshot, source: String) -> String {
        var lines: [String] = []
        lines.append("; Program snapshot metadata")
        lines.append(";   schema: \(snapshot.version)")
        let formatter = ISO8601DateFormatter()
        lines.append(";   created: \(formatter.string(from: snapshot.metadata.createdAt))")
        if let generator = snapshot.metadata.generator {
            lines.append(";   generator: \(generator)")
        }
        lines.append("")
        lines.append(source)
        return lines.joined(separator: "\n")
    }

    private func describeAssemblerError(_ error: AssemblerError) -> String {
        switch error {
        case .invalidOpcode(let line, let mnemonic):
            return "Line \(line): Unknown opcode '\(mnemonic)'."
        case .operandExpected(let line, let opcode):
            return "Line \(line): Opcode \(opcode) expects an operand."
        case .operandUnexpected(let line, let opcode):
            return "Line \(line): Opcode \(opcode) does not take an operand."
        case .addressOutOfRange(let line, let value):
            return "Line \(line): Address \(value) is out of range 0..<\(MailboxAddress.validRange.upperBound)."
        case .literalOutOfRange(let line, let value):
            return "Line \(line): Literal \(value) exceeds word range."
        case .duplicateLabel(let line, let label):
            return "Line \(line): Label '\(label)' is defined more than once."
        case .unresolvedSymbol(let line, let symbol):
            return "Line \(line): Unknown symbol '\(symbol)'."
        case .trailingTokens(let line):
            return "Line \(line): Unexpected tokens after instruction."
        case .programTooLarge(let line):
            return "Line \(line): Program exceeds memory capacity."
        }
    }
}

struct ExecutionService {
    enum Error: Swift.Error, CustomStringConvertible {
        case unsupportedSpeed(Double)
        case programLoadFailed(URL, Swift.Error)
        case snapshotFailure(Swift.Error)

        var description: String {
            switch self {
            case .unsupportedSpeed(let value):
                return "Invalid execution speed: \(value). Provide a value greater than zero."
            case .programLoadFailed(let url, let error):
                return "Failed to load snapshot at \(url.path): \(error.localizedDescription)"
            case .snapshotFailure(let error):
                return "Snapshot error: \(error)"
            }
        }
    }

    struct RunRequest {
        enum Source {
            case programURL(URL)
            case snapshot(ProgramSnapshot)
        }

        var source: Source
        var inbox: [Int]
        var speed: Double?
        var maxCycles: Int?
        var breakpoints: [MailboxAddress]
        var plainOutput: Bool
        var initialState: ProgramState?
        var autoLoadBreakpoints: Bool

        init(source: Source,
             inbox: [Int] = [],
             speed: Double? = nil,
             maxCycles: Int? = nil,
             breakpoints: [MailboxAddress] = [],
             plainOutput: Bool = false,
             initialState: ProgramState? = nil,
             autoLoadBreakpoints: Bool = true) {
            self.source = source
            self.inbox = inbox
            self.speed = speed
            self.maxCycles = maxCycles
            self.breakpoints = breakpoints
            self.plainOutput = plainOutput
            self.initialState = initialState
            self.autoLoadBreakpoints = autoLoadBreakpoints
        }
    }

    struct Outcome {
        let state: ProgramState
        let events: [ExecutionEvent]
        let breakpoint: MailboxAddress?
    }

    let environment: ServiceEnvironment
    private let serializer: ProgramSerializer
    private let breakpointStore: BreakpointStore

    init(environment: ServiceEnvironment) {
        self.environment = environment
        self.serializer = ProgramSerializer()
        self.breakpointStore = BreakpointStore(environment: environment)
    }

    func run(_ request: RunRequest) async throws -> Outcome {
        let prepared = try prepareEngine(request)
        let engine = prepared.engine

        var breakpoint: MailboxAddress?
        do {
            if let speed = request.speed {
                guard speed > 0 else { throw Error.unsupportedSpeed(speed) }
                let schedule = ExecutionSchedule.hertz(speed)
                try await engine.run(schedule: schedule, maxCycles: request.maxCycles)
            } else {
                _ = try engine.runUntilHalt(maxCycles: request.maxCycles)
            }
        } catch let error as ExecutionError {
            switch error {
            case .breakpointHit(let address):
                breakpoint = address
                break
            default:
                throw error
            }
        }

        return Outcome(state: engine.state,
                       events: prepared.recorder.snapshot(),
                       breakpoint: breakpoint)
    }
}

extension ExecutionService {
    struct PreparedExecution {
        let program: Program
        let engine: ExecutionEngine
        let recorder: ExecutionEventRecorder
    }

    func prepareEngine(_ request: RunRequest,
                       additionalObserver: (any ExecutionObserver)? = nil) throws -> PreparedExecution {
        let program: Program
        switch request.source {
        case .programURL(let url):
            do {
                let data = try Data(contentsOf: url)
                program = try serializer.importJSON(data)
            } catch {
                throw Error.programLoadFailed(url, error)
            }
        case .snapshot(let snapshot):
            do {
                program = try Program(snapshot: snapshot)
            } catch {
                throw Error.snapshotFailure(error)
            }
        }

        var initialState = request.initialState ?? ProgramState(inbox: request.inbox)
        if request.initialState != nil {
            for value in request.inbox {
                initialState.enqueueInbox(value)
            }
        }
        initialState.ensureMemoryInitialized(with: program.memoryImage)

        let recorder = ExecutionEventRecorder()
        let observer: any ExecutionObserver
        if let additionalObserver {
            observer = CompositeExecutionObserver(primary: recorder, secondary: additionalObserver)
        } else {
            observer = recorder
        }

        let engine = ExecutionEngine(program: program,
                                     initialState: initialState,
                                     observer: observer)

        // Add explicitly provided breakpoints
        request.breakpoints.forEach { engine.addBreakpoint($0) }

        // Auto-load persisted breakpoints if enabled
        if request.autoLoadBreakpoints {
            let persistedBreakpoints = breakpointStore.getBreakpoints(for: program)
            persistedBreakpoints.forEach { engine.addBreakpoint($0) }
        }

        return PreparedExecution(program: program, engine: engine, recorder: recorder)
    }
}

final class ExecutionEventRecorder: ExecutionObserver, @unchecked Sendable {
    private var storage: [ExecutionEvent] = []
    private let lock = NSLock()

    func handle(_ event: ExecutionEvent) {
        lock.lock()
        storage.append(event)
        lock.unlock()
    }

    func snapshot() -> [ExecutionEvent] {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }
}

private final class CompositeExecutionObserver: ExecutionObserver, @unchecked Sendable {
    private let primary: any ExecutionObserver
    private let secondary: any ExecutionObserver

    init(primary: any ExecutionObserver, secondary: any ExecutionObserver) {
        self.primary = primary
        self.secondary = secondary
    }

    func handle(_ event: ExecutionEvent) {
        primary.handle(event)
        secondary.handle(event)
    }
}

struct SnapshotService {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidName(String)
        case ioFailure(URL, Swift.Error)
        case notFound(String)

        var description: String {
            switch self {
            case .invalidName(let name):
                return "Invalid snapshot name: \(name). Use alphanumerics, dash, or underscore."
            case .ioFailure(let url, let error):
                return "File IO failed for \(url.path): \(error.localizedDescription)"
            case .notFound(let reference):
                return "No snapshot found for \(reference)."
            }
        }
    }

    struct StoreRequest {
        var name: String
        var snapshot: ProgramSnapshot
        var assembly: String?
    }

    struct StoreStateRequest {
        var name: String
        var stateSnapshot: ProgramStateSnapshot
        var programSnapshot: ProgramSnapshot?
    }

    struct ListEntry {
        let name: String
        let programMetadata: SnapshotMetadata
        let location: URL
    }

    // Export/Import structures
    struct ExportBundle: Codable {
        let version: Int
        let metadata: ExportMetadata
        let program: ProgramSnapshot
        let state: ProgramStateSnapshot?
        let assembly: String?
        let breakpoints: [Int]?

        static let currentVersion = 1
    }

    struct ExportMetadata: Codable {
        let exportedAt: Date
        let exportedBy: String?
        let originalName: String
        let description: String?
        let platform: String

        init(originalName: String, description: String? = nil) {
            self.exportedAt = Date()
            self.exportedBy = ProcessInfo.processInfo.processName
            self.originalName = originalName
            self.description = description
            self.platform = ProcessInfo.processInfo.operatingSystemVersionString
        }
    }

    let environment: ServiceEnvironment
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(environment: ServiceEnvironment) {
        self.environment = environment
        self.fileManager = environment.fileManager
        self.encoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            return encoder
        }()
        self.decoder = JSONDecoder()
    }

    func store(_ request: StoreRequest) async throws -> URL {
        let sanitizedName = try validate(name: request.name)
        let programURL = try ensureProgramsDirectory().appendingPathComponent(sanitizedName).appendingPathExtension("json")
        let data: Data
        do {
            data = try encoder.encode(request.snapshot)
        } catch {
            throw Error.ioFailure(programURL, error)
        }
        do {
            try data.write(to: programURL, options: .atomic)
        } catch {
            throw Error.ioFailure(programURL, error)
        }

        if let assembly = request.assembly, !assembly.isEmpty {
            let assemblyURL = programURL.deletingPathExtension().appendingPathExtension("lmc")
            do {
                try assembly.write(to: assemblyURL, atomically: true, encoding: .utf8)
            } catch {
                throw Error.ioFailure(assemblyURL, error)
            }
        }

        return programURL
    }

    func storeState(_ request: StoreStateRequest) async throws -> URL {
        let sanitizedName = try validate(name: request.name)
        let stateURL = try ensureStatesDirectory().appendingPathComponent(sanitizedName).appendingPathExtension("json")

        // Create a combined state and program snapshot if program is provided
        struct CombinedSnapshot: Codable {
            let state: ProgramStateSnapshot
            let program: ProgramSnapshot?
        }

        let combined = CombinedSnapshot(state: request.stateSnapshot, program: request.programSnapshot)

        let data: Data
        do {
            data = try encoder.encode(combined)
        } catch {
            throw Error.ioFailure(stateURL, error)
        }

        do {
            try data.write(to: stateURL, options: .atomic)
        } catch {
            throw Error.ioFailure(stateURL, error)
        }

        return stateURL
    }

    func listSnapshots() throws -> [ListEntry] {
        let directory = try ensureProgramsDirectory(allowCreate: false)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }
        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(at: directory,
                                                           includingPropertiesForKeys: nil,
                                                           options: [.skipsHiddenFiles])
        } catch {
            throw Error.ioFailure(directory, error)
        }

        var entries: [ListEntry] = []
        for url in contents where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                let snapshot = try decoder.decode(ProgramSnapshot.self, from: data)
                let name = url.deletingPathExtension().lastPathComponent
                entries.append(ListEntry(name: name, programMetadata: snapshot.metadata, location: url))
            } catch {
                throw Error.ioFailure(url, error)
            }
        }
        return entries.sorted { $0.name < $1.name }
    }

    func removeSnapshots(named names: [String]) throws {
        guard !names.isEmpty else { return }
        for name in names {
            let sanitized = try validate(name: name)
            let url = try ensureProgramsDirectory().appendingPathComponent(sanitized).appendingPathExtension("json")
            guard fileManager.fileExists(atPath: url.path) else {
                throw Error.notFound(name)
            }
            do {
                try fileManager.removeItem(at: url)
            } catch {
                throw Error.ioFailure(url, error)
            }
            let assemblyURL = url.deletingPathExtension().appendingPathExtension("lmc")
            if fileManager.fileExists(atPath: assemblyURL.path) {
                try? fileManager.removeItem(at: assemblyURL)
            }
        }
    }

    func resolveProgramURL(for reference: String) throws -> URL {
        let expandedReference = expand(reference)
        let candidate = URL(fileURLWithPath: expandedReference)
        if fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        let trimmed = expandedReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameCandidate = (trimmed as NSString).deletingPathExtension
        let preferredName = nameCandidate.isEmpty ? trimmed : nameCandidate
        let sanitized = try validate(name: preferredName)
        let programsDirectory = try ensureProgramsDirectory(allowCreate: false)
        let candidateURL = programsDirectory
            .appendingPathComponent(sanitized)
            .appendingPathExtension("json")
        if fileManager.fileExists(atPath: candidateURL.path) {
            return candidateURL
        }

        throw Error.notFound(reference)
    }

    func resolveSnapshotURL(for reference: String) throws -> URL {
        let expandedReference = expand(reference)
        let candidate = URL(fileURLWithPath: expandedReference)
        if fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        let trimmed = expandedReference.trimmingCharacters(in: .whitespacesAndNewlines)
        let nameCandidate = (trimmed as NSString).deletingPathExtension
        let preferredName = nameCandidate.isEmpty ? trimmed : nameCandidate
        let sanitized = try validate(name: preferredName)

        let programsDirectory = try ensureProgramsDirectory(allowCreate: false)
        let programURL = programsDirectory
            .appendingPathComponent(sanitized)
            .appendingPathExtension("json")
        if fileManager.fileExists(atPath: programURL.path) {
            return programURL
        }

        let statesDirectory = try ensureStatesDirectory(allowCreate: false)
        let stateURL = statesDirectory
            .appendingPathComponent(sanitized)
            .appendingPathExtension("json")
        if fileManager.fileExists(atPath: stateURL.path) {
            return stateURL
        }

        throw Error.notFound(reference)
    }

    func findProgramCompanion(for snapshotURL: URL) throws -> Program? {
        let base = snapshotURL.deletingPathExtension().lastPathComponent
        let programsDirectory = try ensureProgramsDirectory(allowCreate: false)
        let candidate = programsDirectory.appendingPathComponent(base).appendingPathExtension("json")
        guard fileManager.fileExists(atPath: candidate.path) else {
            return nil
        }

        let data = try Data(contentsOf: candidate)
        let snapshot = try decoder.decode(ProgramSnapshot.self, from: data)
        return try Program(snapshot: snapshot)
    }

    func exportProgram(name: String, includeState: Bool = false, description: String? = nil) async throws -> Data {
        // Resolve the program
        let programURL = try resolveProgramURL(for: name)
        let programData = try Data(contentsOf: programURL)
        let programSnapshot = try decoder.decode(ProgramSnapshot.self, from: programData)

        // Load assembly if it exists
        let assemblyURL = programURL.deletingPathExtension().appendingPathExtension("lmc")
        let assembly = fileManager.fileExists(atPath: assemblyURL.path)
            ? try? String(contentsOf: assemblyURL, encoding: .utf8)
            : nil

        // Load state if requested and exists
        var stateSnapshot: ProgramStateSnapshot? = nil
        if includeState {
            let stateDirectory = try ensureStatesDirectory(allowCreate: false)
            let stateName = programURL.deletingPathExtension().lastPathComponent
            let stateURL = stateDirectory.appendingPathComponent(stateName + "-state").appendingPathExtension("json")

            if fileManager.fileExists(atPath: stateURL.path) {
                let stateData = try Data(contentsOf: stateURL)
                struct CombinedSnapshot: Codable {
                    let state: ProgramStateSnapshot
                    let program: ProgramSnapshot?
                }
                let combined = try decoder.decode(CombinedSnapshot.self, from: stateData)
                stateSnapshot = combined.state
            }
        }

        // Load breakpoints if they exist
        let breakpointStore = BreakpointStore(environment: environment)
        let program = try Program(snapshot: programSnapshot)
        let breakpoints = breakpointStore.getBreakpoints(for: program).map { $0.rawValue }

        // Create export bundle
        let bundle = ExportBundle(
            version: ExportBundle.currentVersion,
            metadata: ExportMetadata(originalName: name, description: description),
            program: programSnapshot,
            state: stateSnapshot,
            assembly: assembly,
            breakpoints: breakpoints.isEmpty ? nil : breakpoints
        )

        // Encode with pretty printing
        let exportEncoder = JSONEncoder()
        exportEncoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        exportEncoder.dateEncodingStrategy = .iso8601
        return try exportEncoder.encode(bundle)
    }

    func importProgram(from data: Data, as name: String? = nil) async throws -> (programURL: URL, stateURL: URL?) {
        // Decode the bundle
        let importDecoder = JSONDecoder()
        importDecoder.dateDecodingStrategy = .iso8601
        let bundle = try importDecoder.decode(ExportBundle.self, from: data)

        // Validate version compatibility
        guard bundle.version <= ExportBundle.currentVersion else {
            throw Error.invalidName("Unsupported export version \(bundle.version). Update CLI to import this file.")
        }

        // Determine the name to use
        let targetName = try validate(name: name ?? bundle.metadata.originalName)

        // Store the program
        let programRequest = StoreRequest(
            name: targetName,
            snapshot: bundle.program,
            assembly: bundle.assembly
        )
        let programURL = try await store(programRequest)

        // Store state if included
        var stateURL: URL? = nil
        if let stateSnapshot = bundle.state {
            let stateRequest = StoreStateRequest(
                name: targetName + "-state",
                stateSnapshot: stateSnapshot,
                programSnapshot: bundle.program
            )
            stateURL = try await storeState(stateRequest)
        }

        // Restore breakpoints if included
        if let breakpointAddresses = bundle.breakpoints, !breakpointAddresses.isEmpty {
            let breakpointStore = BreakpointStore(environment: environment)
            let program = try Program(snapshot: bundle.program)
            try breakpointStore.addBreakpoints(breakpointAddresses, to: program, name: targetName)
        }

        return (programURL, stateURL)
    }

    private func ensureProgramsDirectory(allowCreate: Bool = true) throws -> URL {
        let directory = environment.workspace.appendingPathComponent("programs", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else {
            guard allowCreate else { return directory }
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw Error.ioFailure(directory, error)
            }
            return directory
        }
        return directory
    }

    private func ensureStatesDirectory(allowCreate: Bool = true) throws -> URL {
        let directory = environment.workspace.appendingPathComponent("states", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else {
            guard allowCreate else { return directory }
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw Error.ioFailure(directory, error)
            }
            return directory
        }
        return directory
    }

    private func validate(name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, sanitize(trimmed) == trimmed else {
            throw Error.invalidName(name)
        }
        return trimmed
    }

    private func sanitize(_ name: String) -> String {
        name.replacingOccurrences(of: "[^A-Za-z0-9_-]", with: "", options: .regularExpression)
    }

    private func expand(_ reference: String) -> String {
        (reference as NSString).expandingTildeInPath
    }
}

struct BreakpointStore {
    enum Error: Swift.Error, CustomStringConvertible {
        case invalidProgramReference(String)
        case ioFailure(URL, Swift.Error)
        case invalidAddress(Int)
        case noBreakpointsFound(String)

        var description: String {
            switch self {
            case .invalidProgramReference(let reference):
                return "Invalid program reference: \(reference)"
            case .ioFailure(let url, let error):
                return "File IO failed for \(url.path): \(error.localizedDescription)"
            case .invalidAddress(let address):
                return "Invalid breakpoint address: \(address). Must be 0-99."
            case .noBreakpointsFound(let programId):
                return "No breakpoints found for program: \(programId)"
            }
        }
    }

    struct BreakpointSet: Codable {
        let programHash: String
        var programName: String?
        var breakpoints: Set<Int>
        var created: Date
        var modified: Date
    }

    struct BreakpointEntry {
        let address: MailboxAddress
        let programHash: String
        let programName: String?
    }

    let environment: ServiceEnvironment
    private let fileManager: FileManager
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(environment: ServiceEnvironment) {
        self.environment = environment
        self.fileManager = environment.fileManager
        self.encoder = {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            return encoder
        }()
        self.decoder = {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return decoder
        }()
    }

    func computeProgramHash(_ program: Program) -> String {
        let data = program.memoryImage.map { $0.rawValue }.withUnsafeBytes { Data($0) }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func computeProgramHash(_ snapshot: ProgramSnapshot) -> String {
        let data = snapshot.words.withUnsafeBytes { Data($0) }
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func addBreakpoints(_ addresses: [Int], to program: Program, name: String? = nil) throws {
        let programHash = computeProgramHash(program)
        try addBreakpoints(addresses, toProgramHash: programHash, name: name)
    }

    func addBreakpoints(_ addresses: [Int], toProgramHash programHash: String, name: String? = nil) throws {
        for address in addresses {
            guard MailboxAddress.validRange.contains(address) else {
                throw Error.invalidAddress(address)
            }
        }

        var breakpointSet: BreakpointSet
        if let existing = try? loadBreakpointSet(for: programHash) {
            breakpointSet = existing
            breakpointSet.breakpoints.formUnion(addresses)
            breakpointSet.modified = Date()
        } else {
            breakpointSet = BreakpointSet(
                programHash: programHash,
                programName: name,
                breakpoints: Set(addresses),
                created: Date(),
                modified: Date()
            )
        }

        try saveBreakpointSet(breakpointSet)
    }

    func removeBreakpoints(_ addresses: [Int], from program: Program) throws {
        let programHash = computeProgramHash(program)
        try removeBreakpoints(addresses, fromProgramHash: programHash)
    }

    func removeBreakpoints(_ addresses: [Int], fromProgramHash programHash: String) throws {
        guard var breakpointSet = try? loadBreakpointSet(for: programHash) else {
            throw Error.noBreakpointsFound(programHash)
        }

        for address in addresses {
            guard MailboxAddress.validRange.contains(address) else {
                throw Error.invalidAddress(address)
            }
        }

        breakpointSet.breakpoints.subtract(addresses)
        breakpointSet.modified = Date()

        if breakpointSet.breakpoints.isEmpty {
            try deleteBreakpointSet(for: programHash)
        } else {
            try saveBreakpointSet(breakpointSet)
        }
    }

    func clearBreakpoints(for program: Program) throws {
        let programHash = computeProgramHash(program)
        try clearBreakpoints(forProgramHash: programHash)
    }

    func clearBreakpoints(forProgramHash programHash: String) throws {
        try deleteBreakpointSet(for: programHash)
    }

    func getBreakpoints(for program: Program) -> [MailboxAddress] {
        let programHash = computeProgramHash(program)
        return getBreakpoints(forProgramHash: programHash)
    }

    func getBreakpoints(forProgramHash programHash: String) -> [MailboxAddress] {
        guard let breakpointSet = try? loadBreakpointSet(for: programHash) else {
            return []
        }

        return breakpointSet.breakpoints
            .compactMap { MailboxAddress($0) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    func listAllBreakpoints() throws -> [(programHash: String, programName: String?, breakpoints: [MailboxAddress])] {
        let directory = try ensureBreakpointsDirectory(allowCreate: false)
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let contents: [URL]
        do {
            contents = try fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw Error.ioFailure(directory, error)
        }

        var results: [(String, String?, [MailboxAddress])] = []
        for url in contents where url.pathExtension.lowercased() == "json" {
            do {
                let data = try Data(contentsOf: url)
                let breakpointSet = try decoder.decode(BreakpointSet.self, from: data)
                let addresses = breakpointSet.breakpoints
                    .compactMap { MailboxAddress($0) }
                    .sorted { $0.rawValue < $1.rawValue }
                results.append((breakpointSet.programHash, breakpointSet.programName, addresses))
            } catch {
                continue
            }
        }

        return results
    }

    private func loadBreakpointSet(for programHash: String) throws -> BreakpointSet? {
        let url = try ensureBreakpointsDirectory().appendingPathComponent("\(programHash).json")
        guard fileManager.fileExists(atPath: url.path) else { return nil }

        do {
            let data = try Data(contentsOf: url)
            return try decoder.decode(BreakpointSet.self, from: data)
        } catch {
            throw Error.ioFailure(url, error)
        }
    }

    private func saveBreakpointSet(_ breakpointSet: BreakpointSet) throws {
        let url = try ensureBreakpointsDirectory().appendingPathComponent("\(breakpointSet.programHash).json")

        do {
            let data = try encoder.encode(breakpointSet)
            try data.write(to: url, options: .atomic)
        } catch {
            throw Error.ioFailure(url, error)
        }
    }

    private func deleteBreakpointSet(for programHash: String) throws {
        let url = try ensureBreakpointsDirectory().appendingPathComponent("\(programHash).json")

        guard fileManager.fileExists(atPath: url.path) else { return }

        do {
            try fileManager.removeItem(at: url)
        } catch {
            throw Error.ioFailure(url, error)
        }
    }

    private func ensureBreakpointsDirectory(allowCreate: Bool = true) throws -> URL {
        let directory = environment.workspace.appendingPathComponent("breakpoints", isDirectory: true)
        guard fileManager.fileExists(atPath: directory.path) else {
            guard allowCreate else { return directory }
            do {
                try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            } catch {
                throw Error.ioFailure(directory, error)
            }
            return directory
        }
        return directory
    }
}
