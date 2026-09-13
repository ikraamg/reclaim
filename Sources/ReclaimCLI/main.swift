import Foundation
import ReclaimCore

let args = Set(CommandLine.arguments.dropFirst())
let json = args.contains("--json")

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
}

let known: Set<String> = ["--dry-run", "--json", "--self-check", "--disk", "--boot"]
if let stray = args.subtracting(known).sorted().first {
    fail("reclaim: unknown flag \(stray) - refusing to run", code: 2)
}

if args.contains("--self-check") {
    let failures = SelfCheck.failures()
    if failures.isEmpty {
        let live = SelfCheck.shapes.filter { !$0.expectKill }.count
        print("self-check passed: \(live) live shapes protected, \(SelfCheck.shapes.count - live) dead shapes caught")
        exit(0)
    }
    fail(failures.joined(separator: "\n"), code: 1)
}

let config: Config
switch Config.load() {
case .success(let c): config = c
case .failure(let e): fail("reclaim: config unreadable, refusing to guess: \(e)", code: 2)
}

if args.contains("--disk") || args.contains("--boot") {
    let sweep = args.contains("--disk")
        ? DiskSweep.run(disk: config.disk)
        : BootSweep.run(boot: config.boot, header: SystemState.read().header())
    print(json ? SweepReport.json(sweep) : SweepReport.text(sweep), terminator: "")
    exit(0)
}

let dryRun = args.contains("--dry-run")
let processes = ProcessSnapshot.live()
let byPid = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
let me = shell(["/usr/bin/id", "-un"]).trimmingCharacters(in: .whitespacesAndNewlines)
if me.isEmpty { fail("reclaim: cannot determine the current user - refusing to run", code: 2) }
if getuid() == 0 && !dryRun { fail("reclaim: refusing to kill as root - use --dry-run", code: 2) }

// Never touch ourselves or anything above us in the tree.
var untouchable = Ancestry.untouchable(from: getpid(), in: byPid)
untouchable.insert(getppid())  // belt and braces: covers our own pid being absent from the snapshot

let classifier = Classifier(config: config)
for rule in classifier.invalidRules {
    FileHandle.standardError.write(Data("reclaim: ignoring rule \"\(rule.name)\" - invalid regex\n".utf8))
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
let report = RunReport(header: system.header(), evaluation: evaluation, dryRun: dryRun, actions: actions, memoryHogs: hogs)
print(json ? JSONReport.render(report) : TextReport.render(report), terminator: "")
