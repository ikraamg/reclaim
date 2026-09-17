import Foundation

/// The app's view of the world between ticks. Pure: the app feeds it reports and configs, it answers what to show.
public struct Monitor: Sendable {
    public struct ConfigError: Equatable, Sendable {
        public var message: String
        public var since: Date
    }

    public enum Event: Equatable, Sendable {
        case killCandidate(Finding)
        case killed(Finding, action: String)
        case sustained(Alert)
    }

    public var config: Config
    public var report: RunReport?
    public var lastTick: Date?
    public var changedAt: Date?
    public var runState = RunState()
    public var configError: ConfigError?
    public var hasLoadedConfig = false
    public var lastError: String?
    public var pending: Set<Int32> = []
    public var manualActions: [Int32: String] = [:]
    public var notified: Set<Int32> = []
    public var announcedKills: Set<Int32> = []
    public var sustained = Sustained()
    public var timeZone: TimeZone

    public init(config: Config = Config(), timeZone: TimeZone = .current) {
        self.config = config
        self.timeZone = timeZone
    }

    // MARK: Mutations

    /// Returns what is new this tick: KILL rows not announced before, automatic kills, and alerts that just fired.
    @discardableResult
    public mutating func apply(_ report: RunReport, at now: Date) -> [Event] {
        if !report.evaluation.unchanged || changedAt == nil { changedAt = now }
        self.report = report
        lastTick = now
        lastError = nil
        runState = report.evaluation.state
        let alive = Set(report.evaluation.findings.map(\.process.pid))
        manualActions = manualActions.filter { alive.contains($0.key) }
        pending = pending.intersection(alive)
        notified = notified.intersection(alive)
        announcedKills = announcedKills.intersection(alive)
        var events: [Event] = []
        for f in report.evaluation.findings where f.verdict == .kill {
            if let action = report.actions[f.process.pid] {
                if !announcedKills.contains(f.process.pid) {
                    events.append(.killed(f, action: action))
                    announcedKills.insert(f.process.pid)
                }
            } else if report.dryRun && !notified.contains(f.process.pid) {
                events.append(.killCandidate(f))
                notified.insert(f.process.pid)
            }
        }
        events += sustained.observe(hot: report.hotProcesses, system: report.system, alerts: config.alerts, at: now).map(Event.sustained)
        return events
    }

    public mutating func apply(failure: PipelineError, at now: Date) {
        lastError = "could not check processes: \(failure)"
        lastTick = now
    }

    public mutating func apply(config: Config) {
        self.config = config
        configError = nil
        hasLoadedConfig = true
    }

    /// The first rejection sets the time; later ones keep it, so the banner says when the file broke.
    public mutating func reject(configMessage: String, at now: Date) {
        if configError == nil { configError = ConfigError(message: configMessage, since: now) }
    }

    public mutating func beginKill(_ pid: Int32) { pending.insert(pid) }

    public mutating func finishKill(_ pid: Int32, result: String) {
        pending.remove(pid)
        manualActions[pid] = result
    }

    // MARK: Derived

    public var findings: [Finding] { report?.evaluation.findings ?? [] }
    public var killRows: [Finding] { sorted(findings.filter { $0.verdict == .kill }) }
    public var reportRows: [Finding] { sorted(findings.filter { $0.verdict == .report }) }
    public var killCount: Int { killRows.count }
    public var killTitle: String { (report?.dryRun ?? true) ? "WOULD KILL" : "KILLED" }
    public var showsKillAll: Bool { killRows.contains { action(for: $0.process.pid) == nil } }
    public var hogs: [ProcessRecord] { report?.memoryHogs ?? [] }
    public var hogsTitle: String? { hogs.isEmpty ? nil : "SWAP OVER 80% · biggest residents, whoever they belong to" }
    public var header: String { report?.header ?? "" }
    public var isEmpty: Bool { findings.isEmpty && hogs.isEmpty }

    public var emptyDetail: String {
        guard let report, let lastTick else { return "Checking…" }
        return "\(report.processCount) processes checked at \(clock(lastTick, seconds: true))."
    }

    public var footer: String {
        guard let lastTick else { return "checking…" }
        if isEmpty { return "every \(config.pollSeconds)s" }
        var text = clock(lastTick, seconds: true)
        if let changedAt, changedAt < lastTick { text += " · same since \(clock(changedAt))" }
        return text
    }

    public var banner: String? {
        if let configError {
            return hasLoadedConfig
                ? "config.json invalid since \(clock(configError.since)) · using the last good one"
                : "config.json invalid · using defaults"
        }
        if let lastError { return lastError }
        if let rules = report?.invalidRules, !rules.isEmpty {
            return rules.map { "rule \"\($0.name)\" ignored - invalid regex" }.joined(separator: "\n")
        }
        return nil
    }

    /// What happened to this pid: the pipeline's action, a manual kill's result, or "killing…" while one is in flight.
    public func action(for pid: Int32) -> String? {
        if pending.contains(pid) { return "killing…" }
        return report?.actions[pid] ?? manualActions[pid]
    }

    /// Wedged rows are other users' processes, neverKill entries or rule-less hogs; the CLI already says "not safe to kill".
    public static func canKill(_ finding: Finding) -> Bool { finding.category != "wedged" }

    func sorted(_ rows: [Finding]) -> [Finding] {
        rows.sorted { (band(of: $0.process), -$0.process.rssKB) < (band(of: $1.process), -$1.process.rssKB) }
    }

    func clock(_ date: Date, seconds: Bool = false) -> String {
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = seconds ? "HH:mm:ss" : "HH:mm"
        return f.string(from: date)
    }
}
