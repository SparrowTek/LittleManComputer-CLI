import Foundation

/// Manages command history for the REPL with persistence
final class CommandHistory {
    private var history: [String] = []
    private var currentIndex: Int = 0
    private let maxHistorySize: Int
    private let historyURL: URL
    private let fileManager = FileManager.default

    init(maxSize: Int = 500, historyFile: URL? = nil) {
        self.maxHistorySize = maxSize

        // Determine history file location
        if let customFile = historyFile {
            self.historyURL = customFile
        } else {
            let home = fileManager.homeDirectoryForCurrentUser
            let lmcDir = home.appendingPathComponent(".lmc", isDirectory: true)
            self.historyURL = lmcDir.appendingPathComponent("repl_history")
        }

        // Load existing history
        loadHistory()
    }

    /// Add a command to history
    func add(_ command: String) {
        let trimmed = command.trimmingCharacters(in: .whitespacesAndNewlines)

        // Don't add empty commands or duplicates of the last command
        guard !trimmed.isEmpty else { return }
        if let last = history.last, last == trimmed { return }

        // Add to history
        history.append(trimmed)

        // Trim history if it exceeds max size
        if history.count > maxHistorySize {
            history.removeFirst(history.count - maxHistorySize)
        }

        // Reset index to end
        currentIndex = history.count

        // Save to disk
        saveHistory()
    }

    /// Get previous command (up arrow)
    func previous() -> String? {
        guard !history.isEmpty else { return nil }

        if currentIndex > 0 {
            currentIndex -= 1
        }

        return history.indices.contains(currentIndex) ? history[currentIndex] : nil
    }

    /// Get next command (down arrow)
    func next() -> String? {
        guard !history.isEmpty else { return nil }

        if currentIndex < history.count - 1 {
            currentIndex += 1
            return history[currentIndex]
        } else if currentIndex < history.count {
            currentIndex = history.count
            return "" // Return to empty prompt
        }

        return nil
    }

    /// Reset navigation to the end of history
    func resetNavigation() {
        currentIndex = history.count
    }

    /// Get all history entries
    func allEntries() -> [String] {
        return history
    }

    /// Clear all history
    func clear() {
        history.removeAll()
        currentIndex = 0
        saveHistory()
    }

    /// Search history for commands containing a substring
    func search(containing substring: String) -> [String] {
        let lowercased = substring.lowercased()
        return history.filter { $0.lowercased().contains(lowercased) }
    }

    /// Get the N most recent commands
    func recent(_ count: Int = 10) -> [String] {
        guard count > 0 else { return [] }
        let startIndex = max(0, history.count - count)
        return Array(history[startIndex..<history.count])
    }

    // MARK: - Private Methods

    private func loadHistory() {
        guard fileManager.fileExists(atPath: historyURL.path) else { return }

        do {
            let contents = try String(contentsOf: historyURL, encoding: .utf8)
            history = contents
                .components(separatedBy: .newlines)
                .filter { !$0.isEmpty }

            // Trim to max size if needed
            if history.count > maxHistorySize {
                history = Array(history.suffix(maxHistorySize))
            }

            currentIndex = history.count
        } catch {
            // Silently fail - history is not critical
        }
    }

    private func saveHistory() {
        // Ensure directory exists
        let directory = historyURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: directory.path) {
            try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        // Write history
        let contents = history.joined(separator: "\n")
        try? contents.write(to: historyURL, atomically: true, encoding: .utf8)
    }
}

// MARK: - History Display Extension

extension CommandHistory {
    /// Format history for display
    func formatHistory(numbered: Bool = true, recent: Int? = nil) -> String {
        let entries = recent.map { self.recent($0) } ?? allEntries()

        if entries.isEmpty {
            return "No history available"
        }

        if numbered {
            let startNumber = recent.map { history.count - $0 + 1 } ?? 1
            return entries.enumerated().map { index, command in
                let number = startNumber + index
                return String(format: "%4d  %s", number, command)
            }.joined(separator: "\n")
        } else {
            return entries.joined(separator: "\n")
        }
    }
}