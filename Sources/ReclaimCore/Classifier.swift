import Foundation

public enum Verdict: String, Codable {
    case kill = "KILL"
    case report = "REPORT"
}

public struct Finding: Equatable {
    public var process: ProcessRecord
    public var category: String
    public var verdict: Verdict
    public var reason: String
}

public struct Context {
    public var processes: [ProcessRecord]
    public var me: String
    public var untouchable: Set<Int32>
    public var listeners: [Int: Set<Int32>]?
    public var cwds: [Int32: String]
    public var worktreeNote: (String?) -> String
    public private(set) var byPid: [Int32: ProcessRecord]

    public init(processes: [ProcessRecord], me: String, untouchable: Set<Int32>,
                listeners: [Int: Set<Int32>]?, cwds: [Int32: String],
                worktreeNote: @escaping (String?) -> String) {
        self.processes = processes; self.me = me; self.untouchable = untouchable
        self.listeners = listeners; self.cwds = cwds; self.worktreeNote = worktreeNote
        self.byPid = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { a, _ in a })
    }
}

public struct Classifier {
    let config: Config
    let compiled: [(Rule, NSRegularExpression)]

    /// Rules dropped because their pattern failed to compile. Still dropped, but no longer silent.
    public let invalidRules: [Rule]

    public init(config: Config) {
        self.config = config
        // A rule with a bad regex is dropped, never guessed at.
        var compiled: [(Rule, NSRegularExpression)] = []
        var invalidRules: [Rule] = []
        for rule in config.rules {
            if let regex = try? NSRegularExpression(pattern: rule.match) {
                compiled.append((rule, regex))
            } else {
                invalidRules.append(rule)
            }
        }
        self.compiled = compiled
        self.invalidRules = invalidRules
    }

    /// Processes some portUnbound rule matches — the only ones worth an lsof probe.
    public func portCandidates(in processes: [ProcessRecord]) -> [ProcessRecord] {
        let portRules = compiled.filter { $0.0.evidence == .portUnbound }
        return processes.filter { p in
            let range = NSRange(p.command.startIndex..., in: p.command)
            return portRules.contains { $0.1.firstMatch(in: p.command, range: range) != nil }
        }
    }

    public func classify(_ p: ProcessRecord, in ctx: Context) -> Finding? {
        if p.user != ctx.me || ctx.untouchable.contains(p.pid) { return wedged(p) }
        if config.neverKill.contains(where: { p.command.contains($0) }) { return wedged(p) }

        for (rule, regex) in compiled {
            let range = NSRange(p.command.startIndex..., in: p.command)
            guard let match = regex.firstMatch(in: p.command, range: range) else { continue }
            return apply(rule, match: match, to: p, in: ctx)
        }
        return wedged(p)
    }

    func apply(_ rule: Rule, match: NSTextCheckingResult, to p: ProcessRecord, in ctx: Context) -> Finding? {
        let old = p.age >= rule.minAgeSeconds
        switch rule.evidence {
        case .orphaned:
            if p.ppid == 1 && old {
                return Finding(process: p, category: rule.name, verdict: .kill,
                               reason: "orphaned \(rule.name), parent long gone")
            }
            // Only spin loops are worth reporting when young; a parented watcher is just a watcher.
            if rule.name == "busy-loop" {
                return Finding(process: p, category: rule.name, verdict: .report,
                               reason: "spin loop, but young or still parented - may be a live benchmark")
            }
            return nil

        case .parentDead:
            let parentAlive = ctx.byPid[p.ppid] != nil
            if !parentAlive && old {
                return Finding(process: p, category: rule.name, verdict: .kill,
                               reason: "\(rule.name), its parent is gone")
            }
            if p.age >= 2 * 86400 {
                return Finding(process: p, category: rule.name, verdict: .report,
                               reason: "\(human(age: p.age)) old but parent \(p.ppid) is alive")
            }
            return nil

        case .portUnbound:
            guard let listeners = ctx.listeners, !listeners.isEmpty else {
                return Finding(process: p, category: rule.name, verdict: .report,
                               reason: "cannot see the listener table - not judging this")
            }
            guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: p.command),
                  let port = Int(p.command[r]) else {
                return Finding(process: p, category: rule.name, verdict: .report,
                               reason: "rule has no port capture group - not judging this")
            }
            let holders = listeners[port] ?? []
            var family: Set<Int32> = [p.pid, p.ppid]
            family.formUnion(ctx.processes.filter { $0.ppid == p.pid }.map(\.pid))
            if !old {
                return Finding(process: p, category: rule.name, verdict: .report,
                               reason: "under \(rule.minAgeSeconds / 60)m old, may still be booting")
            }
            if !holders.isDisjoint(with: family) { return nil }  // serving traffic
            if let other = holders.min() {
                return Finding(process: p, category: rule.name, verdict: .kill,
                               reason: "port \(port) is held by pid \(other), this one never bound")
            }
            return Finding(process: p, category: rule.name, verdict: .kill,
                           reason: "nothing is listening on port \(port)\(ctx.worktreeNote(ctx.cwds[p.pid]))")
        }
    }

    /// Things we will never kill, but will mention when they are clearly wedged.
    func wedged(_ p: ProcessRecord) -> Finding? {
        guard p.cpu >= config.wedged.percent, p.age >= config.wedged.minAgeSeconds else { return nil }
        let cpu = String(format: "%.0f%% CPU for %@", p.cpu, human(age: p.age))
        if config.respawnsClean.contains(where: { p.command.contains($0) }) {
            return Finding(process: p, category: "wedged", verdict: .report,
                           reason: "\(cpu) - killall respawns it clean")
        }
        return Finding(process: p, category: "wedged", verdict: .report,
                       reason: "\(cpu) - not safe to kill, worth a look")
    }
}

/// 10d 4h · 4h 10m · 55m — same shape as the Python's human_age.
public func human(age seconds: Int) -> String {
    let d = seconds / 86400, h = (seconds % 86400) / 3600, m = (seconds % 3600) / 60
    if d > 0 { return "\(d)d \(h)h" }
    if h > 0 { return "\(h)h \(m)m" }
    return "\(m)m"
}
