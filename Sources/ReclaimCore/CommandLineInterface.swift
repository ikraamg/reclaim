import Foundation

/// The `reclaim` binary's behavior as a function, so the app can host it and tests can call it.
public enum CommandLineInterface {
    public static let knownFlags: Set<String> = ["--dry-run", "--json", "--self-check", "--disk", "--boot", "--kill"]

    /// Returns the exit status. Output goes through the writers so tests can capture it.
    public static func run(_ arguments: [String],
                           stdout: (String) -> Void = { print($0, terminator: "") },
                           stderr: (String) -> Void = { FileHandle.standardError.write(Data($0.utf8)) }) -> Int32 {
        let args = Set(arguments)
        let json = args.contains("--json")
        if let stray = args.subtracting(knownFlags).sorted().first {
            stderr("reclaim: unknown flag \(stray) - refusing to run\n")
            return 2
        }
        if args.contains("--disk") && args.contains("--boot") {
            stderr("reclaim: pick one of --disk or --boot\n")
            return 2
        }
        if args.contains("--self-check") {
            let failures = SelfCheck.failures()
            guard failures.isEmpty else { stderr(failures.joined(separator: "\n") + "\n"); return 1 }
            let live = SelfCheck.shapes.filter { !$0.expectKill }.count
            stdout("self-check passed: \(live) live shapes protected, \(SelfCheck.shapes.count - live) dead shapes caught\n")
            return 0
        }

        let config: Config
        switch Config.load() {
        case .success(let c): config = c
        case .failure(let e): stderr("reclaim: config unreadable, refusing to guess: \(e)\n"); return 2
        }

        if args.contains("--disk") || args.contains("--boot") {
            let sweep = args.contains("--disk")
                ? DiskSweep.run(disk: config.disk)
                : BootSweep.run(boot: config.boot, header: SystemState.read().header())
            stdout(json ? SweepReport.json(sweep) : SweepReport.text(sweep))
            return 0
        }

        // --dry-run always wins. Otherwise kill only if the config says so or --kill overrides for this run.
        let dryRun = args.contains("--dry-run") || !(config.autoKill || args.contains("--kill"))
        var report: RunReport
        switch Pipeline.run(config: config, dryRun: dryRun, previous: RunState.load()) {
        case .success(let r): report = r
        case .failure(.unknownUser): stderr("reclaim: cannot determine the current user - refusing to run\n"); return 2
        case .failure(.rootWithoutDryRun): stderr("reclaim: refusing to kill as root - use --dry-run\n"); return 2
        }
        report.evaluation.state.save()
        for rule in report.invalidRules {
            stderr("reclaim: ignoring rule \"\(rule.name)\" - invalid regex\n")
        }
        if !args.contains("--dry-run") && dryRun && report.evaluation.findings.contains(where: { $0.verdict == .kill }) {
            report.hint = "reporting only - set \"autoKill\": true in config or pass --kill"
        }
        stdout(json ? JSONReport.render(report) : TextReport.render(report))
        return 0
    }
}
