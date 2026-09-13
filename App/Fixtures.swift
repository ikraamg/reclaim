import Foundation
import ReclaimCore

/// Monitors for --render. Each shows one state of the popover with believable data.
enum Fixtures {
    static let names = ["findings", "killed", "empty", "unchanged", "badConfig", "swap"]

    static let t0 = Date(timeIntervalSince1970: 1_789_044_990)   // 12:56:30 UTC
    static let header = "swap 2.1/4.0GB (52%)  ·  up 3d 4h  ·  battery 81% discharging"

    static func record(_ pid: Int32, cpu: Double, mb: Int, age: Int, command: String) -> ProcessRecord {
        ProcessRecord(pid: pid, ppid: 1, cpu: cpu, rssKB: mb * 1024, age: age, user: "me", command: command)
    }

    static let puma = Finding(process: record(48213, cpu: 0, mb: 412, age: 4 * 3600 + 600, command: "puma 8.0.2 (tcp://localhost:3000) [core]"),
                              category: "dev-server", verdict: .kill, reason: "nothing is listening on port 3000")
    static let orphanLoop = Finding(process: record(51102, cpu: 99.8, mb: 4, age: 2 * 3600 + 180, command: "zsh -c while :; do :; done"),
                                    category: "busy-loop", verdict: .kill, reason: "orphaned busy-loop, parent long gone")
    static let orbstack = Finding(process: record(9911, cpu: 54, mb: 890, age: 86400 + 4 * 3600, command: "/Applications/OrbStack.app/Contents/MacOS/OrbStack Helper"),
                                  category: "wedged", verdict: .report, reason: "54% CPU for 1d 4h - not safe to kill, worth a look")
    static let youngLoop = Finding(process: record(51230, cpu: 99.1, mb: 4, age: 720, command: "zsh -c while :; do :; done"),
                                   category: "busy-loop", verdict: .report, reason: "spin loop, but young or still parented - may be a live benchmark")

    static func report(_ findings: [Finding], dryRun: Bool = true, unchanged: Bool = false, actions: [Int32: String] = [:],
                       hogs: [ProcessRecord] = [], invalidRules: [Rule] = []) -> RunReport {
        RunReport(header: header, evaluation: Evaluation(findings: findings, unchanged: unchanged, swapJustHot: !hogs.isEmpty, state: RunState()),
                  dryRun: dryRun, actions: actions, memoryHogs: hogs, processCount: 412, invalidRules: invalidRules)
    }

    static func monitor(named name: String) -> Monitor? {
        var m = Monitor(config: Config(), timeZone: TimeZone(identifier: "UTC")!)
        m.apply(config: Config())
        switch name {
        case "findings":
            m.apply(report([puma, orphanLoop, orbstack, youngLoop]), at: t0)
        case "killed":
            m.apply(report([puma, orphanLoop, orbstack], dryRun: false,
                           actions: [48213: "terminated", 51102: "killed (-9, ignored TERM)"]), at: t0)
        case "empty":
            m.apply(report([]), at: t0)
        case "unchanged":
            m.apply(report([puma, youngLoop]), at: t0.addingTimeInterval(-270))
            m.apply(report([puma, youngLoop], unchanged: true), at: t0)
        case "badConfig":
            m.apply(report([orphanLoop]), at: t0)
            m.reject(configMessage: "typeMismatch(pollSeconds)", at: t0.addingTimeInterval(-120))
        case "swap":
            let hogs = [record(3301, cpu: 2, mb: 6_100, age: 86400, command: "/Applications/Xcode.app/Contents/MacOS/Xcode"),
                        record(880, cpu: 1, mb: 3_900, age: 3 * 86400, command: "/Applications/Arc.app/Contents/Frameworks/Arc Helper (Renderer)"),
                        record(9911, cpu: 54, mb: 890, age: 86400, command: "/Applications/OrbStack.app/Contents/MacOS/OrbStack Helper")]
            m.apply(report([orphanLoop], hogs: hogs), at: t0)
        default:
            return nil
        }
        return m
    }
}
