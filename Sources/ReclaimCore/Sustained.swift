import Foundation

public enum AlertKind: String, Equatable, Sendable { case cpu, memory, swap, thermal, battery }

public struct Alert: Equatable, Sendable {
    public var kind: AlertKind
    public var pid: Int32?
    public var title: String
    public var detail: String
    public init(kind: AlertKind, pid: Int32?, title: String, detail: String) {
        self.kind = kind; self.pid = pid; self.title = title; self.detail = detail
    }
}

/// Fires once when a condition has held long enough, and again only after it cleared. Pure; the app ticks it.
public struct Sustained: Equatable, Sendable {
    struct Key: Hashable, Sendable { var kind: AlertKind; var pid: Int32? }
    struct BatterySample: Equatable, Sendable { var at: Date; var percent: Int }

    var since: [Key: Date] = [:]
    var fired: Set<Key> = []
    var holding: Set<Key> = []
    var batterySamples: [BatterySample] = []

    public init() {}

    public mutating func observe(hot: [ProcessRecord], system: SystemState, alerts: Alerts, at now: Date) -> [Alert] {
        holding = []
        var out: [Alert] = []
        for p in hot {
            if p.cpu >= alerts.cpu.percent, let held = hold(Key(kind: .cpu, pid: p.pid), minutes: alerts.cpu.minutes, at: now) {
                out.append(Alert(kind: .cpu, pid: p.pid, title: "CPU · \(p.name)", detail: "\(Int(p.cpu.rounded()))% for \(human(age: held)) (pid \(p.pid))"))
            }
            if Double(p.rssKB) >= alerts.memory.gigabytes * 1_048_576, let held = hold(Key(kind: .memory, pid: p.pid), minutes: alerts.memory.minutes, at: now) {
                out.append(Alert(kind: .memory, pid: p.pid, title: "Memory · \(p.name)",
                                 detail: String(format: "%.1fGB for %@ (pid %d)", Double(p.rssKB) / 1_048_576, human(age: held), p.pid)))
            }
        }
        if let pct = system.swapPercent, pct >= alerts.swapPercent, cross(Key(kind: .swap, pid: nil)) {
            out.append(Alert(kind: .swap, pid: nil, title: "Swap \(Int(pct.rounded()))%", detail: "biggest residents are in the popover"))
        }
        if alerts.thermal, !system.thermal.isEmpty, cross(Key(kind: .thermal, pid: nil)) {
            out.append(Alert(kind: .thermal, pid: nil, title: "Thermal pressure", detail: system.thermal.joined(separator: "; ")))
        }
        if let alert = battery(system, alerts: alerts, at: now) { out.append(alert) }
        since = since.filter { holding.contains($0.key) }
        fired = fired.intersection(holding)
        return out
    }

    /// Seconds the condition has held, the first time it has held for at least `minutes`; nil otherwise.
    mutating func hold(_ key: Key, minutes: Int, at now: Date) -> Int? {
        holding.insert(key)
        let start = since[key] ?? now
        since[key] = start
        let held = Int(now.timeIntervalSince(start))
        guard held >= minutes * 60, !fired.contains(key) else { return nil }
        fired.insert(key)
        return held
    }

    /// True the first tick a machine-level condition holds; false until it has cleared and returned.
    mutating func cross(_ key: Key) -> Bool {
        holding.insert(key)
        if fired.contains(key) { return false }
        fired.insert(key)
        return true
    }

    mutating func battery(_ system: SystemState, alerts: Alerts, at now: Date) -> Alert? {
        guard system.batteryState == "discharging", let pct = system.batteryPercent else { batterySamples = []; return nil }
        batterySamples.append(BatterySample(at: now, percent: pct))
        batterySamples.removeAll { now.timeIntervalSince($0.at) > 3600 }
        guard let first = batterySamples.first, now.timeIntervalSince(first.at) >= 900 else { return nil }
        let span = now.timeIntervalSince(first.at)
        let rate = Double(first.percent - pct) / (span / 3600)
        guard rate >= alerts.batteryDrainPerHour, cross(Key(kind: .battery, pid: nil)) else { return nil }
        return Alert(kind: .battery, pid: nil, title: "Battery draining \(Int(rate.rounded()))%/h",
                     detail: "from \(first.percent)% to \(pct)% in \(human(age: Int(span)))")
    }
}
