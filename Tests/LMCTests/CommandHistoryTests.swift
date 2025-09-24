import Foundation
import Testing
@testable import LMC

@Suite("CommandHistory Tests")
struct CommandHistoryTests {

    @Test func testAddCommand() async throws {
        // Use a temporary file for isolation
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let history = CommandHistory(maxSize: 10, historyFile: tempFile)

        history.add("load test")
        history.add("run")
        history.add("state")

        let entries = history.allEntries()
        #expect(entries.count == 3)
        #expect(entries[0] == "load test")
        #expect(entries[1] == "run")
        #expect(entries[2] == "state")
    }

    @Test func testNoDuplicateLastCommand() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let history = CommandHistory(maxSize: 10, historyFile: tempFile)

        history.add("load test")
        history.add("load test") // Should not be added as duplicate
        history.add("run")

        let entries = history.allEntries()
        #expect(entries.count == 2)
        #expect(entries[0] == "load test")
        #expect(entries[1] == "run")
    }

    @Test func testMaxSizeLimit() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let history = CommandHistory(maxSize: 3, historyFile: tempFile)

        history.add("cmd1")
        history.add("cmd2")
        history.add("cmd3")
        history.add("cmd4") // Should remove cmd1

        let entries = history.allEntries()
        #expect(entries.count == 3)
        #expect(entries[0] == "cmd2")
        #expect(entries[1] == "cmd3")
        #expect(entries[2] == "cmd4")
    }

    @Test func testNavigation() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let history = CommandHistory(maxSize: 10, historyFile: tempFile)

        history.add("first")
        history.add("second")
        history.add("third")

        // Navigate backwards
        #expect(history.previous() == "third")
        #expect(history.previous() == "second")
        #expect(history.previous() == "first")
        #expect(history.previous() == "first") // Should stay at first

        // Navigate forward
        #expect(history.next() == "second")
        #expect(history.next() == "third")
        #expect(history.next() == "") // Should return empty for new command
    }

    @Test func testSearch() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let history = CommandHistory(maxSize: 10, historyFile: tempFile)

        history.add("load test1")
        history.add("save myfile")
        history.add("load test2")
        history.add("run")

        let loadMatches = history.search(containing: "load")
        #expect(loadMatches.count == 2)
        #expect(loadMatches.contains("load test1"))
        #expect(loadMatches.contains("load test2"))

        let testMatches = history.search(containing: "test")
        #expect(testMatches.count == 2)
    }

    @Test func testRecent() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let history = CommandHistory(maxSize: 10, historyFile: tempFile)

        history.add("cmd1")
        history.add("cmd2")
        history.add("cmd3")
        history.add("cmd4")
        history.add("cmd5")

        let recent = history.recent(3)
        #expect(recent.count == 3)
        #expect(recent[0] == "cmd3")
        #expect(recent[1] == "cmd4")
        #expect(recent[2] == "cmd5")
    }

    @Test func testClear() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let history = CommandHistory(maxSize: 10, historyFile: tempFile)

        history.add("cmd1")
        history.add("cmd2")
        history.clear()

        #expect(history.allEntries().isEmpty)
        #expect(history.previous() == nil)
    }

    @Test func testFormatHistory() async throws {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempFile) }

        let history = CommandHistory(maxSize: 10, historyFile: tempFile)

        history.add("load test")
        history.add("run")
        history.add("state")

        let formatted = history.formatHistory(numbered: true)
        #expect(formatted.contains("load test"))
        #expect(formatted.contains("run"))
        #expect(formatted.contains("state"))

        // Test with recent limit
        let recentFormatted = history.formatHistory(numbered: true, recent: 2)
        #expect(recentFormatted.contains("run"))
        #expect(recentFormatted.contains("state"))
        #expect(!recentFormatted.contains("load test"))
    }

    @Test func testPersistence() async throws {
        // Create a temporary directory for testing
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let historyFile = tempDir.appendingPathComponent("test_history")

        // Create history and add commands
        do {
            let history = CommandHistory(maxSize: 10, historyFile: historyFile)
            history.add("load test")
            history.add("run")
            history.add("state")
        }

        // Create new history instance and verify persistence
        do {
            let history = CommandHistory(maxSize: 10, historyFile: historyFile)
            let entries = history.allEntries()
            #expect(entries.count == 3)
            #expect(entries[0] == "load test")
            #expect(entries[1] == "run")
            #expect(entries[2] == "state")
        }
    }
}