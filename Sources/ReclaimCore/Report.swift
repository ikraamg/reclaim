import Foundation

/// Pretty, sorted, slash-unescaped JSON; "{}" when encoding fails.
public func jsonString<T: Encodable>(_ value: T) -> String {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    return String(decoding: (try? encoder.encode(value)) ?? Data("{}".utf8), as: UTF8.self)
}

public enum Band: Int, Comparable {
    case burningCPU, holdingMemory, idleWeight

    public var title: String {
        switch self {
        case .burningCPU: return "burning CPU"
        case .holdingMemory: return "holding memory"
        case .idleWeight: return "waking the CPU / idle weight"
        }
    }

    public static func < (a: Band, b: Band) -> Bool { a.rawValue < b.rawValue }
}

public func band(of p: ProcessRecord) -> Band {
    if p.cpu >= 20 { return .burningCPU }
    if p.rssKB >= 200 * 1024 { return .holdingMemory }
    return .idleWeight
}

// String(format:) ignores width flags on %@, so pad by hand.
func pad(_ s: String, _ width: Int) -> String {
    s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
}

public struct RunReport: Sendable {
    public var header: String
    public var evaluation: Evaluation
    public var dryRun: Bool
    public var actions: [Int32: String]
    public var memoryHogs: [ProcessRecord]
    public var processCount: Int
    public var invalidRules: [Rule]
    public var hint: String? = nil

    public init(header: String, evaluation: Evaluation, dryRun: Bool, actions: [Int32: String], memoryHogs: [ProcessRecord],
                processCount: Int = 0, invalidRules: [Rule] = [], hint: String? = nil) {
        self.header = header; self.evaluation = evaluation; self.dryRun = dryRun
        self.actions = actions; self.memoryHogs = memoryHogs; self.processCount = processCount
        self.invalidRules = invalidRules; self.hint = hint
    }
}

public enum TextReport {
    public static func render(_ r: RunReport) -> String {
        let findings = r.evaluation.findings
        var out = ""
        if r.evaluation.unchanged {
            let what = findings.isEmpty ? "nothing to clean" : "same \(findings.count) item(s) as last run"
            out += "reclaim: \(what), unchanged for \(r.evaluation.state.quietRuns) runs.  \(r.header)\n"
            if r.evaluation.swapJustHot { out += hogs(r.memoryHogs) }
            return out
        }
        if findings.isEmpty {
            out += "reclaim: nothing to clean.  \(r.header)\n"
            if !r.memoryHogs.isEmpty { out += hogs(r.memoryHogs) }
            return out
        }
        out += r.header + "\n"
        if !r.memoryHogs.isEmpty { out += hogs(r.memoryHogs) }
        out += "\n"
        let titles: [(Verdict, String)] = [(.kill, r.dryRun ? "WOULD KILL" : "KILLED"), (.report, "REPORTED - your call")]
        let groups: [(String, [Finding])] = titles.compactMap { verdict, title in
            let group = findings.filter { $0.verdict == verdict }
                .sorted { (band(of: $0.process), -$0.process.rssKB) < (band(of: $1.process), -$1.process.rssKB) }
            return group.isEmpty ? nil : (title, group)
        }
        for (index, (title, group)) in groups.enumerated() {
            out += "\(title) (\(group.count))\n"
            var last: Band?
            for f in group {
                let b = band(of: f.process)
                if b != last { last = b; out += "  ~ \(b.title)\n" }
                let action = r.actions[f.process.pid].map { "  -> \($0)" } ?? ""
                let cpu = String(format: "%5.1f", f.process.cpu)
                let mb = String(format: "%6d", f.process.rssKB / 1024)
                out += "    \(pad(String(f.process.pid), 6)) \(pad(f.category, 12)) \(cpu)%cpu \(mb)MB  "
                out += "\(pad(human(age: f.process.age), 8))  \(f.process.command.prefix(90))\n"
                out += "           \(f.reason)\(action)\n"
            }
            // Blank line separates groups; no trailing blank line after the last one.
            if index < groups.count - 1 { out += "\n" }
        }
        if let hint = r.hint { out += hint + "\n" }
        return out
    }

    static func hogs(_ procs: [ProcessRecord]) -> String {
        var out = "swap is over 80%. Biggest resident processes, whoever they belong to:\n"
        for p in procs {
            let gb = String(format: "%6.1f", Double(p.rssKB) / 1_048_576)
            out += "  \(pad(String(p.pid), 6)) \(gb)GB  \(p.command.prefix(70))\n"
        }
        return out
    }
}

public enum JSONReport {
    struct Row: Encodable {
        let pid: Int32, ppid: Int32, category: String, verdict: String, reason: String
        let cpu: Double, rssMB: Int, ageSeconds: Int, age: String, band: String, user: String, command: String
        let action: String?

        enum CodingKeys: String, CodingKey {
            case pid, ppid, category, verdict, reason, cpu, rssMB, ageSeconds, age, band, user, command, action
        }

        // Every key must be present so agents get a fixed schema; encodeIfPresent would
        // drop "action" entirely for REPORT rows instead of writing it as null.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(pid, forKey: .pid)
            try c.encode(ppid, forKey: .ppid)
            try c.encode(category, forKey: .category)
            try c.encode(verdict, forKey: .verdict)
            try c.encode(reason, forKey: .reason)
            try c.encode(cpu, forKey: .cpu)
            try c.encode(rssMB, forKey: .rssMB)
            try c.encode(ageSeconds, forKey: .ageSeconds)
            try c.encode(age, forKey: .age)
            try c.encode(band, forKey: .band)
            try c.encode(user, forKey: .user)
            try c.encode(command, forKey: .command)
            try c.encode(action, forKey: .action)
        }
    }
    struct Hog: Encodable { let pid: Int32, rssMB: Int, command: String }
    struct Body: Encodable {
        let header: String, dryRun: Bool, unchanged: Bool, quietRuns: Int, swapJustHot: Bool
        let findings: [Row], memoryHogs: [Hog]
        let hint: String?

        enum CodingKeys: String, CodingKey {
            case header, dryRun, unchanged, quietRuns, swapJustHot, findings, memoryHogs, hint
        }

        // Every key must be present so agents get a fixed schema; encodeIfPresent would
        // drop "hint" entirely when there is none instead of writing it as null.
        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            try c.encode(header, forKey: .header)
            try c.encode(dryRun, forKey: .dryRun)
            try c.encode(unchanged, forKey: .unchanged)
            try c.encode(quietRuns, forKey: .quietRuns)
            try c.encode(swapJustHot, forKey: .swapJustHot)
            try c.encode(findings, forKey: .findings)
            try c.encode(memoryHogs, forKey: .memoryHogs)
            try c.encode(hint, forKey: .hint)
        }
    }

    public static func render(_ r: RunReport) -> String {
        let rows = r.evaluation.findings.map { f in
            Row(pid: f.process.pid, ppid: f.process.ppid, category: f.category, verdict: f.verdict.rawValue,
                reason: f.reason, cpu: f.process.cpu, rssMB: f.process.rssKB / 1024, ageSeconds: f.process.age,
                age: human(age: f.process.age), band: band(of: f.process).title, user: f.process.user,
                command: f.process.command, action: r.actions[f.process.pid])
        }
        let hogs = r.memoryHogs.map { Hog(pid: $0.pid, rssMB: $0.rssKB / 1024, command: $0.command) }
        let body = Body(header: r.header, dryRun: r.dryRun, unchanged: r.evaluation.unchanged,
                        quietRuns: r.evaluation.state.quietRuns, swapJustHot: r.evaluation.swapJustHot,
                        findings: rows, memoryHogs: hogs, hint: r.hint)
        return jsonString(body)
    }
}
