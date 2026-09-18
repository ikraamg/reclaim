import AppKit
import os
import ReclaimCore

@main
enum Main {
    @MainActor static func main() {
        let args = Array(CommandLine.arguments.dropFirst())
        if args.contains("--render") { Render.run(args) }
        if args.first == "--cli" { exit(CommandLineInterface.run(Array(args.dropFirst()))) }
        if args.first?.hasPrefix("--") == true { exit(CommandLineInterface.run(args)) }
        // A second launch quits: two instances mean two status items and every banner twice.
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
        if others.contains(where: { $0.processIdentifier != getpid() }) {
            Logger(subsystem: "com.ikraam.Reclaim", category: "launch").notice("already running, quitting this instance")
            exit(0)
        }
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
}
