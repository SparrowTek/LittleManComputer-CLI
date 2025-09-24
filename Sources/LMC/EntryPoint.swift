@preconcurrency import ArgumentParser

@main
struct LMCEntryPoint {
    static func main() async {
        await LMCCommand.main()
    }
}
