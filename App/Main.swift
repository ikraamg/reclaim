import AppKit
import ReclaimCore

@main
enum Main {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--render") { Render.run(args) }
        if args.first?.hasPrefix("--") == true { exit(CommandLineInterface.run(args)) }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
