import Foundation
import ArgumentParser
import CoreLittleManComputer

struct LMC: ParsableCommand {
    static let configuration = CommandConfiguration(
        abstract: "A Swift command-line tool to compile, step, and run a Little Man Computer program",
        subcommands: [
            Compile.self,
            Step.self,
            Run.self
        ])
    
    init() { }
}

LMC.main()

struct Compile: ParsableCommand {
    @Argument var code: String? // TODO: how to make the argument optional?
    @Option(name: .shortAndLong, help: "Set the file to compile code from a file") var file: String
    
    mutating func run() throws {
        printRegisters()
        
        if let code {
            print("CODE: \(code)")
        }
    }
}

struct Step: ParsableCommand {
    mutating func run() throws {
        printRegisters()
    }
}

struct Run: ParsableCommand {
    @Option(wrappedValue: 0.2, name: .shortAndLong, help: "Set the speed to a double value of the percentage of a second that should be between each step of the running program")
    private var speed: Double
    
    mutating func run() throws {
        printRegisters()
        print("SPEED: \(speed)")
    }
}

fileprivate var program: Program?
fileprivate func printRegisters() {
    print("""
    Memory Registers

        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------
          000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000  |  000
        -------------------------------------------------------------------------------

""")
}
