import Foundation
import ReclaimCore

/// Monitors and sweeps for --render. Each shows one state of the popover or the sweeps window with believable data.
enum Fixtures {
    static let names = ["findings", "killed", "empty", "unchanged", "badConfig", "swap", "disk", "boot"]

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

    /// Sweeps for --render: "disk" has the disk sweep landed with boot still running; "boot" has only the boot sweep.
    static func sweeps(named name: String) -> Sweeps? {
        switch name {
        case "disk": return Sweeps(disk: diskSweep, running: ["boot"], startedAt: t0.addingTimeInterval(-38))
        case "boot": return Sweeps(boot: bootSweep, ranAt: t0, seconds: 38)
        default: return nil
        }
    }

    static let diskSweep = Sweep(
        kind: "disk",
        header: ["disk: 612GB used, 314GB free (66% full)  ·  nothing below is deleted automatically"],
        sections: [
            SweepSection(title: "docker", bytes: 14_200_000_000, lines: [
                SweepLine(bytes: 9_800_000_000, label: "images", detail: "41 total, 6 active", command: "docker image prune -a"),
                SweepLine(bytes: 4_400_000_000, label: "build cache", detail: "212 total, 0 active", command: "docker builder prune"),
                SweepLine(bytes: 2_100_000_000, label: "volumes", detail: "2 look like data (core_pgdata, core_redis) - leave alone, never `docker volume prune`")]),
            SweepSection(title: "git worktrees", bytes: 3_700_000_000, lines: [
                SweepLine(bytes: 6_900_000_000, label: "core", detail: "7 worktrees, 2 clean and untouched for 21+ days (2.31GB)"),
                SweepLine(bytes: 1_400_000_000, label: "fix-render-timeouts", detail: "34d, tracked",
                          command: "git -C '/Users/me/Documents/GitHub/core' worktree remove '/Users/me/Documents/GitHub/core.worktrees/fix-render-timeouts'", nested: true),
                SweepLine(bytes: 910_000_000, label: "spike-clickhouse", detail: "58d, untracked by git",
                          command: "rm -rf '/Users/me/Documents/GitHub/core.worktrees/spike-clickhouse'", nested: true),
                SweepLine(bytes: 1_400_000_000, label: "node_modules/tmp", detail: "inside worktrees you still use",
                          command: "rm -rf ~/Documents/GitHub/core.worktrees/*/{node_modules,tmp}", nested: true),
                SweepLine(label: "", detail: "check each one first - a worktree is unpushed work until proven otherwise")]),
            SweepSection(title: "caches", bytes: 2_600_000_000, lines: [
                SweepLine(bytes: 1_900_000_000, label: "~/.local/share/mise", detail: "3 unused runtime versions (of 4.10GB installed - only these go)", command: "mise prune"),
                SweepLine(bytes: 700_000_000, label: "~/Library/Developer/Xcode/DerivedData", detail: "rebuilt on next build", command: "rm -rf ~/Library/Developer/Xcode/DerivedData/*")]),
        ],
        footer: ["total reclaimable: 19.09GB"])

    static let bootSweep = Sweep(
        kind: "boot",
        header: ["boot: what starts with you and what has been burning CPU since boot  ·  \(header)",
                 "nothing below is changed automatically"],
        sections: [
            SweepSection(title: "cpu hogs (>20% for >1h)", bytes: nil, lines: [
                SweepLine(label: "mds_stores", detail: "38% CPU for 5h 12m (pid 402)"),
                SweepLine(label: "", detail: "Spotlight indexing - exclude repo dirs: System Settings > Spotlight > Search Privacy", nested: true)]),
            SweepSection(title: "login items (System Settings > General > Login Items to change)", bytes: nil, lines: [
                SweepLine(label: "Reclaim"), SweepLine(label: "Raycast"), SweepLine(label: "Rize")]),
            SweepSection(title: "launch agents/daemons outside boot.keep (unload, then move the plist to the Trash)", bytes: nil, lines: [
                SweepLine(label: "~/Library/LaunchAgents/com.adobe.AAM.Updater-1.0.plist",
                          command: "launchctl bootout gui/$(id -u) '/Users/me/Library/LaunchAgents/com.adobe.AAM.Updater-1.0.plist'")]),
            SweepSection(title: "orphaned system extensions", bytes: nil, lines: [
                SweepLine(label: "activated_enabled", detail: "app gone: /Applications/Tailscale.app"),
                SweepLine(label: "", detail: "reinstall the signed app, LAUNCH it, then Finder-trash it while it runs (systemextensionsctl uninstall needs SIP off)", nested: true)]),
            SweepSection(title: "homebrew data dirs of stopped postgres versions", bytes: nil, lines: []),
        ],
        footer: [])
}
