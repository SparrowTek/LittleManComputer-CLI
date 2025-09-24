import Foundation

enum LMCExitCode: Int32 {
    case success = 0
    case assemblyError = 1
    case runtimeError = 2
    case ioError = 3
    case usage = 64
}

func emitError(_ message: String) {
    guard !message.isEmpty else { return }
    FileHandle.standardError.write(Data((message + "\n").utf8))
}
