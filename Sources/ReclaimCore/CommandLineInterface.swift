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
        let processes = ProcessSnapshot.live()
        let byPid = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
        let me = (shell(["/usr/bin/id", "-un"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if me.isEmpty { stderr("reclaim: cannot determine the current user - refusing to run\n"); return 2 }
        if getuid() == 0 && !dryRun { stderr("reclaim: refusing to kill as root - use --dry-run\n"); return 2 }

        // Never touch ourselves or anything above us in the tree.
        var untouchable = Ancestry.untouchable(from: getpid(), in: byPid)
        untouchable.insert(getppid())  // belt and braces: covers our own pid being absent from the snapshot

        let classifier = Classifier(config: config)
        for rule in classifier.invalidRules {
            stderr("reclaim: ignoring rule \"\(rule.name)\" - invalid regex\n")
        }

        let candidates = classifier.portCandidates(in: processes)
        let cwds = Dictionary(candidates.compactMap { p in Probe.cwd(of: p.pid).map { (p.pid, $0) } }, uniquingKeysWith: { a, _ in a })
        let context = Context(processes: processes, me: me, untouchable: untouchable,
                              listeners: candidates.isEmpty ? [:] : Probe.listeners(),
                              cwds: cwds, worktreeNote: Worktree.note(cwd:))

        let findings = processes.compactMap { classifier.classify($0, in: context) }
        let system = SystemState.read()
        let swapHot = (system.swapPercent ?? 0) >= 80
        let evaluation = Session.evaluate(findings, previous: RunState.load(), swapHot: swapHot, willKill: !dryRun)
        evaluation.state.save()

        var actions: [Int32: String] = [:]
        if !dryRun && !evaluation.unchanged {
            for f in evaluation.findings where f.verdict == .kill {
                actions[f.process.pid] = Terminate.run(pid: f.process.pid)
            }
        }
        let hogs = swapHot ? Array(processes.sorted { $0.rssKB > $1.rssKB }.prefix(5)) : []
        var report = RunReport(header: system.header(), evaluation: evaluation, dryRun: dryRun, actions: actions, memoryHogs: hogs)
        if !args.contains("--dry-run") && dryRun && evaluation.findings.contains(where: { $0.verdict == .kill }) {
            report.hint = "reporting only - set \"autoKill\": true in config or pass --kill"
        }
        stdout(json ? JSONReport.render(report) : TextReport.render(report))
        return 0
    }
}
