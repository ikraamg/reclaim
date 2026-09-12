import Foundation
import ReclaimCore

let args = Set(CommandLine.arguments.dropFirst())
let json = args.contains("--json")

func fail(_ message: String, code: Int32) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(code)
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

if args.contains("--disk") || args.contains("--boot") {
    fail("not ported yet - run /usr/bin/python3 ~/.claude/skills/reclaim/reclaim.py \(args.contains("--disk") ? "--disk" : "--boot")", code: 2)
}

let config: Config
switch Config.load() {
case .success(let c): config = c
case .failure(let e): fail("reclaim: config unreadable, refusing to guess: \(e)", code: 2)
}

let dryRun = args.contains("--dry-run")
let processes = ProcessSnapshot.live()
let byPid = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
let me = shell(["id", "-un"]).trimmingCharacters(in: .whitespacesAndNewlines)

// Never touch ourselves or anything above us in the tree. Walk the full ancestor
// chain (matching reclaim.py's ancestors()) rather than stopping at the direct parent.
var untouchable: Set<Int32> = [0, 1, getpid(), getppid()]
var cursor: Int32? = getpid()
var seen: Set<Int32> = []
while let pid = cursor, pid > 1, !seen.contains(pid) {
    seen.insert(pid)
    guard let p = byPid[pid] else { break }
    untouchable.insert(pid)
    cursor = p.ppid
}

let classifier = Classifier(config: config)
for rule in classifier.invalidRules {
    FileHandle.standardError.write(Data("reclaim: ignoring rule \"\(rule.name)\" - invalid regex\n".utf8))
}

let portRules = config.rules.filter { $0.evidence == .portUnbound }
    .compactMap { try? NSRegularExpression(pattern: $0.match) }
let candidates = processes.filter { p in
    portRules.contains { $0.firstMatch(in: p.command, range: NSRange(p.command.startIndex..., in: p.command)) != nil }
}
let cwds = Dictionary(uniqueKeysWithValues: candidates.compactMap { p in Probe.cwd(of: p.pid).map { (p.pid, $0) } })
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
