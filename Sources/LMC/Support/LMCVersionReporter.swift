import CoreLittleManComputer

struct LMCVersionReporter {
    static let cliVersion = "0.1.0-dev"

    static var banner: String {
        "LittleManComputer CLI \(cliVersion) (ProgramSnapshot v\(ProgramSnapshot.currentVersion); ProgramStateSnapshot v\(ProgramStateSnapshot.currentVersion))"
    }

    func printVersion(printer: (String) -> Void = { print($0) }) {
        printer(Self.banner)
        printer("CoreLittleManComputer snapshot schemas:")
        printer("  Program: \(ProgramSnapshot.currentVersion)")
        printer("  Program state: \(ProgramStateSnapshot.currentVersion)")
    }
}
