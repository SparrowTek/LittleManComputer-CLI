import Foundation

struct ServiceEnvironment {
    let workspace: URL
    let colorMode: ColorMode
    let verbosity: Verbosity
    let fileManager: FileManager
    let theme: TerminalThemeChoice
    let compactOutput: Bool

    init(options: GlobalOptions, fileManager: FileManager = .default) {
        self.workspace = options.resolveWorkspaceURL(fileManager: fileManager)
        self.colorMode = options.effectiveColorMode
        self.verbosity = options.effectiveVerbosity
        self.fileManager = fileManager
        self.theme = options.theme
        self.compactOutput = options.useCompactOutput
    }
}
