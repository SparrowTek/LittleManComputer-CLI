import ConsoleKitTerminal
import Foundation

struct CommandContext {
    let globalOptions: GlobalOptions
    let environment: ServiceEnvironment
    let services: ServiceRegistry
    let terminal: Terminal?
    let theme: TerminalThemeChoice
    let compactOutput: Bool

    init(globalOptions: GlobalOptions, fileManager: FileManager = .default) {
        self.globalOptions = globalOptions
        self.environment = ServiceEnvironment(options: globalOptions, fileManager: fileManager)
        self.services = ServiceRegistry(environment: environment)
        if globalOptions.plain {
            self.terminal = nil
        } else {
            let terminal = Terminal()
            switch globalOptions.effectiveColorMode {
            case .always:
                terminal.stylizedOutputOverride = true
            case .never:
                terminal.stylizedOutputOverride = false
            case .auto:
                break
            }
            self.terminal = terminal
        }
        self.theme = globalOptions.theme
        self.compactOutput = globalOptions.useCompactOutput
    }
}
