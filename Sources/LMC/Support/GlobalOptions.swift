@preconcurrency import ArgumentParser
import Foundation

struct GlobalOptions: ParsableArguments {
    @Option(name: [.customShort("w"), .long], help: "Override the workspace directory (default: ~/.lmc)")
    var workspace: String?

    @Option(name: .long, help: "Control colour output for terminal rendering")
    var color: ColorMode = .auto

    @Option(name: .long, help: "Set logging verbosity")
    var verbosity: Verbosity = .info

    @Option(name: .long, help: "Select output theme (default, monochrome, high-contrast)")
    var theme: TerminalThemeChoice = .default

    @Flag(name: .long, help: "Use compact state output (omit grid views)")
    var compact: Bool = false

    @Flag(name: .long, help: "Emit plain output (disables colour and quiets logs)")
    var plain: Bool = false

    @Flag(name: .long, help: "Print CLI and core version information, then exit")
    var version: Bool = false

    var showVersion: Bool { version }

    var effectiveColorMode: ColorMode {
        plain ? .never : color
    }

    var effectiveVerbosity: Verbosity {
        plain ? .quiet : verbosity
    }

    var useCompactOutput: Bool { compact }

    func resolveWorkspaceURL(fileManager: FileManager = .default) -> URL {
        if let override = workspace, !override.isEmpty {
            return URL(fileURLWithPath: override).standardizedFileURL
        }
        let home = fileManager.homeDirectoryForCurrentUser
        return home.appendingPathComponent(".lmc", isDirectory: true)
    }
}

enum ColorMode: String, ExpressibleByArgument, CaseIterable, Sendable {
    case auto
    case always
    case never
}

enum Verbosity: String, ExpressibleByArgument, CaseIterable, Sendable {
    case quiet
    case info
    case debug
}

enum TerminalThemeChoice: String, ExpressibleByArgument, CaseIterable, Sendable {
    case `default`
    case monochrome
    case highContrast = "high-contrast"
}
