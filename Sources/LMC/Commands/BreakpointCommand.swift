@preconcurrency import ArgumentParser
import CoreLittleManComputer
import Foundation

struct BreakpointCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "break",
        abstract: "Manage persistent breakpoints for LMC programs",
        discussion: "Breakpoints are stored persistently and automatically loaded when running programs.",
        subcommands: [Add.self, Remove.self, Clear.self, List.self],
        defaultSubcommand: List.self
    )
}

extension BreakpointCommand {
    struct Add: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Add breakpoints to a program",
            discussion: """
                Add persistent breakpoints to a program. These breakpoints will be automatically
                loaded whenever the program is run.

                Examples:
                  lmc break add program.json 10 20 30
                  lmc break add my-saved-program 15 25 --name "My Program"
                """
        )

        @OptionGroup var options: GlobalOptions

        @Argument(
            help: "Program file path or saved snapshot name",
            completion: .file(extensions: ["json", "lmc"])
        )
        var program: String

        @Argument(
            help: "Mailbox addresses (0-99) to add as breakpoints",
            transform: { str in
                guard let value = Int(str) else {
                    throw ValidationError("Invalid address '\(str)': must be an integer")
                }
                guard MailboxAddress.validRange.contains(value) else {
                    throw ValidationError("Address \(value) out of range: must be 0-99")
                }
                return value
            }
        )
        var addresses: [Int]

        @Option(
            name: .long,
            help: "Friendly name for the program (for display purposes)"
        )
        var name: String?

        func run() throws {
            let env = ServiceEnvironment(options: options)
            let registry = ServiceRegistry(environment: env)

            // Load the program to compute its hash
            let programURL = try registry.snapshot.resolveProgramURL(for: program)
            let data = try Data(contentsOf: programURL)
            let snapshot = try JSONDecoder().decode(ProgramSnapshot.self, from: data)
            let program = try Program(snapshot: snapshot)

            // Add breakpoints
            try registry.breakpoints.addBreakpoints(addresses, to: program, name: name)

            // Provide feedback
            let addressList = addresses.map { String(format: "%03d", $0) }.joined(separator: ", ")
            print("✓ Added breakpoints at mailboxes \(addressList)")

            // Show current breakpoints for this program
            let current = registry.breakpoints.getBreakpoints(for: program)
            if !current.isEmpty {
                print("Current breakpoints: \(current.map { String(format: "%03d", $0.rawValue) }.joined(separator: ", "))")
            }
        }
    }

    struct Remove: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Remove breakpoints from a program",
            discussion: """
                Remove specific breakpoints from a program.

                Examples:
                  lmc break remove program.json 10 20
                  lmc break remove my-saved-program 15
                """
        )

        @OptionGroup var options: GlobalOptions

        @Argument(
            help: "Program file path or saved snapshot name",
            completion: .file(extensions: ["json", "lmc"])
        )
        var program: String

        @Argument(
            help: "Mailbox addresses to remove from breakpoints",
            transform: { str in
                guard let value = Int(str) else {
                    throw ValidationError("Invalid address '\(str)': must be an integer")
                }
                guard MailboxAddress.validRange.contains(value) else {
                    throw ValidationError("Address \(value) out of range: must be 0-99")
                }
                return value
            }
        )
        var addresses: [Int]

        func run() throws {
            let env = ServiceEnvironment(options: options)
            let registry = ServiceRegistry(environment: env)

            // Load the program
            let programURL = try registry.snapshot.resolveProgramURL(for: program)
            let data = try Data(contentsOf: programURL)
            let snapshot = try JSONDecoder().decode(ProgramSnapshot.self, from: data)
            let program = try Program(snapshot: snapshot)

            // Remove breakpoints
            try registry.breakpoints.removeBreakpoints(addresses, from: program)

            // Provide feedback
            let addressList = addresses.map { String(format: "%03d", $0) }.joined(separator: ", ")
            print("✓ Removed breakpoints at mailboxes \(addressList)")

            // Show remaining breakpoints
            let remaining = registry.breakpoints.getBreakpoints(for: program)
            if !remaining.isEmpty {
                print("Remaining breakpoints: \(remaining.map { String(format: "%03d", $0.rawValue) }.joined(separator: ", "))")
            } else {
                print("No breakpoints remaining for this program")
            }
        }
    }

    struct Clear: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "Clear all breakpoints for a program",
            discussion: """
                Remove all breakpoints from a program.

                Example:
                  lmc break clear program.json
                  lmc break clear my-saved-program
                """
        )

        @OptionGroup var options: GlobalOptions

        @Argument(
            help: "Program file path or saved snapshot name",
            completion: .file(extensions: ["json", "lmc"])
        )
        var program: String

        @Option(
            name: .shortAndLong,
            help: "Skip confirmation prompt"
        )
        var force: Bool = false

        func run() throws {
            let env = ServiceEnvironment(options: options)
            let registry = ServiceRegistry(environment: env)

            // Load the program
            let programURL = try registry.snapshot.resolveProgramURL(for: program)
            let data = try Data(contentsOf: programURL)
            let snapshot = try JSONDecoder().decode(ProgramSnapshot.self, from: data)
            let program = try Program(snapshot: snapshot)

            // Check if there are any breakpoints to clear
            let existing = registry.breakpoints.getBreakpoints(for: program)
            if existing.isEmpty {
                print("No breakpoints to clear for this program")
                return
            }

            // Confirm unless forced
            if !force {
                print("Clear \(existing.count) breakpoint(s) for this program? (y/N): ", terminator: "")
                let response = readLine()?.lowercased()
                if response != "y" && response != "yes" {
                    print("Cancelled")
                    return
                }
            }

            // Clear breakpoints
            try registry.breakpoints.clearBreakpoints(for: program)
            print("✓ Cleared all breakpoints for the program")
        }
    }

    struct List: ParsableCommand {
        static let configuration = CommandConfiguration(
            abstract: "List breakpoints for programs",
            discussion: """
                List breakpoints for a specific program or all programs.

                Examples:
                  lmc break list                    # List all breakpoints
                  lmc break list program.json       # List breakpoints for specific program
                """
        )

        @OptionGroup var options: GlobalOptions

        @Argument(
            help: "Optional program file path or saved snapshot name",
            completion: .file(extensions: ["json", "lmc"])
        )
        var program: String?

        @Option(
            name: .long,
            help: "Output format"
        )
        var format: OutputFormat = .text

        enum OutputFormat: String, ExpressibleByArgument {
            case text
            case json
        }

        func run() throws {
            let env = ServiceEnvironment(options: options)
            let registry = ServiceRegistry(environment: env)

            if let programRef = program {
                // List breakpoints for specific program
                let programURL = try registry.snapshot.resolveProgramURL(for: programRef)
                let data = try Data(contentsOf: programURL)
                let snapshot = try JSONDecoder().decode(ProgramSnapshot.self, from: data)
                let program = try Program(snapshot: snapshot)

                let breakpoints = registry.breakpoints.getBreakpoints(for: program)
                let programHash = registry.breakpoints.computeProgramHash(program)

                switch format {
                case .text:
                    if breakpoints.isEmpty {
                        print("No breakpoints set for this program")
                    } else {
                        print("Breakpoints for program (hash: \(String(programHash.prefix(8)))...):")
                        for bp in breakpoints {
                            print("  • Mailbox \(String(format: "%03d", bp.rawValue))")
                        }
                    }
                case .json:
                    let output = [
                        "programHash": programHash,
                        "breakpoints": breakpoints.map { $0.rawValue }
                    ] as [String: Any]
                    let jsonData = try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
                    print(String(data: jsonData, encoding: .utf8)!)
                }
            } else {
                // List all breakpoints
                let allBreakpoints = try registry.breakpoints.listAllBreakpoints()

                switch format {
                case .text:
                    if allBreakpoints.isEmpty {
                        print("No breakpoints set for any programs")
                    } else {
                        print("Breakpoints by program:")
                        for (hash, name, breakpoints) in allBreakpoints {
                            let displayName = name ?? "Unnamed"
                            print("\n\(displayName) (hash: \(String(hash.prefix(8)))...):")
                            for bp in breakpoints {
                                print("  • Mailbox \(String(format: "%03d", bp.rawValue))")
                            }
                        }
                    }
                case .json:
                    let output = allBreakpoints.map { hash, name, breakpoints in
                        [
                            "programHash": hash,
                            "programName": name as Any,
                            "breakpoints": breakpoints.map { $0.rawValue }
                        ]
                    }
                    let jsonData = try JSONSerialization.data(withJSONObject: output, options: .prettyPrinted)
                    print(String(data: jsonData, encoding: .utf8)!)
                }
            }
        }
    }
}