import Foundation

public enum DiskSweep {
    static let home = FileManager.default.homeDirectoryForCurrentUser.path

    static func tilde(_ path: String) -> String {
        path.hasPrefix(home) ? "~" + path.dropFirst(home.count) : path
    }

    static func shellQuoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func gigabytesTrimmed(_ bytes: Int64) -> String { gigabytes(bytes).trimmingCharacters(in: .whitespaces) }

    static func duBytes(_ path: String) -> Int64 { DiskParse.duTotal(shell(["/usr/bin/du", "-sxk", path], timeout: 60) ?? "") }

    static func isDir(_ path: String) -> Bool {
        var d: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
    }

    public static func run(disk: Disk) -> Sweep {
        var header: [String] = []
        let df = (shell(["/bin/df", "-g", "/System/Volumes/Data"]) ?? "").split(separator: "\n")
        if df.count > 1 {
            let f = df[1].split(separator: " ", omittingEmptySubsequences: true)
            if f.count > 4 {
                header.append("disk: \(f[2])GB used, \(f[3])GB free (\(f[4]) full)  ·  nothing below is deleted automatically")
            }
        }
        var sections = [docker(disk), worktrees(disk), caches(disk)]
        sections.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        var footer = ["total reclaimable: \(gigabytesTrimmed(sections.reduce(0) { $0 + ($1.bytes ?? 0) }))"]
        if !(shell(["sh", "-c", "command -v mo"]) ?? "").isEmpty {
            footer.append("not counted above, mole owns these (interactive, both take --dry-run):")
            footer.append("  mo clean    caches this table misses - app leftovers, iOS backups, conda, maven")
            footer.append("  mo purge    node_modules/dist/target/Pods across every repo in ~/.config/mole/purge_paths")
        }
        return Sweep(kind: "disk", header: header, sections: sections, footer: footer)
    }

    static func docker(_ disk: Disk) -> SweepSection {
        guard !(shell(["sh", "-c", "command -v docker"]) ?? "").isEmpty else { return SweepSection(title: "docker", bytes: 0, lines: []) }
        let summary = DiskParse.dockerSummary(shell(["docker", "system", "df", "--format", "{{json .}}"]) ?? "")
        guard !summary.isEmpty else {
            return SweepSection(title: "docker", bytes: 0, lines: [SweepLine(label: "", detail: "  docker is installed but not running", command: nil)])
        }
        var lines: [SweepLine] = []
        var total: Int64 = 0
        for (kind, cmd) in [("Images", "docker image prune -a"), ("Containers", "docker container prune"), ("Build Cache", "docker builder prune")] {
            guard let row = summary[kind], row.reclaimableBytes > 100_000_000 else { continue }
            total += row.reclaimableBytes
            lines.append(SweepLine(label: "", detail: String(format: "  %@  %@ %d total, %@ active   %@",
                                                gigabytes(row.reclaimableBytes) as NSString, pad(kind, 13) as NSString,
                                                row.totalCount, row.active as NSString, cmd as NSString),
                                   command: cmd))
        }
        let volumes = DiskParse.dockerVolumes(shell(["docker", "system", "df", "-v"]) ?? "")
        let byKind = Dictionary(grouping: volumes) { DiskParse.volumeKind($0.name, disk: disk) }
        let free = (byKind[.rebuildable] ?? []).filter { $0.links == 0 }
        if !free.isEmpty {
            let size = free.reduce(0) { $0 + $1.bytes }
            total += size
            lines.append(SweepLine(label: "", detail: "  \(gigabytes(size))  volumes       \(free.count) unused and rebuildable (node_modules, bundle, assets)", command: nil))
            let names = free.map(\.name).sorted()
            let cmd = "docker volume rm " + names.prefix(6).joined(separator: " ") + (names.count > 6 ? " ..." : "")
            lines.append(SweepLine(label: "", detail: "            " + cmd, command: cmd))
        }
        if let data = byKind[.data], !data.isEmpty {
            let names = data.map(\.name).sorted().prefix(3).joined(separator: ", ")
            lines.append(SweepLine(label: "", detail: "  \(gigabytes(data.reduce(0) { $0 + $1.bytes }))  volumes       \(data.count) look like data (\(names)) - leave alone, never `docker volume prune`", command: nil))
        }
        let unknown = (byKind[.unknown] ?? []).filter { $0.links == 0 && $0.bytes > 100_000_000 }
        if !unknown.isEmpty {
            lines.append(SweepLine(label: "", detail: "  \(gigabytes(unknown.reduce(0) { $0 + $1.bytes }))  volumes       \(unknown.count) unnamed and unclassified - `docker volume inspect` before deleting", command: nil))
        }
        return SweepSection(title: "docker", bytes: total, lines: lines)
    }

    static func worktrees(_ disk: Disk) -> SweepSection {
        var lines: [SweepLine] = []
        var staleTotal: Int64 = 0
        let root = (disk.worktreeRoot as NSString).expandingTildeInPath
        let roots = ((try? FileManager.default.contentsOfDirectory(atPath: root)) ?? [])
            .filter { $0.hasSuffix(".worktrees") }.sorted().map { root + "/" + $0 }
        for worktreeRoot in roots {
            let sizes = DiskParse.duChildren(shell(["sh", "-c", "/usr/bin/du -sxk \(shellQuoted(worktreeRoot))/*/ 2>/dev/null"], timeout: 120) ?? "")
            if sizes.isEmpty { continue }
            let repoName = (worktreeRoot as NSString).lastPathComponent.replacingOccurrences(of: ".worktrees", with: "")
            let repo = (worktreeRoot as NSString).deletingLastPathComponent + "/" + repoName
            let tracked = Worktree.tracked(in: repo)
            var stale: [(bytes: Int64, path: String, days: Int, tracked: Bool)] = []
            for (path, bytes) in sizes {
                let raw = (shell(["git", "-C", path, "log", "-1", "--format=%ct"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let days = Int(raw).map { Int((Date().timeIntervalSince1970 - Double($0)) / 86400) } ?? 0
                let dirty = !(shell(["git", "-C", path, "status", "--porcelain"]) ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !dirty && days > disk.worktreeStaleDays { stale.append((bytes, path, days, tracked.contains(path))) }
            }
            let total = sizes.values.reduce(0, +)
            let staleBytes = stale.reduce(0) { $0 + $1.bytes }
            staleTotal += staleBytes
            lines.append(SweepLine(label: "", detail: "  \(gigabytes(total))  \(pad(repoName, 14)) \(sizes.count) worktrees, \(stale.count) clean and untouched for \(disk.worktreeStaleDays)+ days (\(gigabytesTrimmed(staleBytes)))", command: nil))
            for s in stale.sorted(by: { $0.bytes > $1.bytes }).prefix(5) {
                let name = String((s.path as NSString).lastPathComponent.prefix(42))
                let cmd = s.tracked ? "git -C \(shellQuoted(repo)) worktree remove \(shellQuoted(s.path))" : "rm -rf \(shellQuoted(s.path))"
                lines.append(SweepLine(label: "", detail: "            \(gigabytes(s.bytes))  \(pad(name, 42)) \(String(format: "%3d", s.days))d  \(s.tracked ? "git worktree remove" : "untracked by git, rm -rf")", command: cmd))
            }
            let globs = disk.regenerableInRepo.map { "\(shellQuoted(worktreeRoot))/*/\($0)" }.joined(separator: " ")
            let junk = DiskParse.duTotal(shell(["sh", "-c", "/usr/bin/du -sxk \(globs) 2>/dev/null"], timeout: 120) ?? "")
            if junk > 200_000_000 {
                staleTotal += junk
                let cmd = "rm -rf \(tilde(worktreeRoot))/*/{\(disk.regenerableInRepo.joined(separator: ","))}"
                lines.append(SweepLine(label: "", detail: "            \(gigabytesTrimmed(junk)) of \(disk.regenerableInRepo.joined(separator: "/")) inside worktrees you still use - \(cmd)", command: cmd))
            }
        }
        if !lines.isEmpty {
            lines.append(SweepLine(label: "", detail: "            check each one first - a worktree is unpushed work until proven otherwise", command: nil))
        }
        return SweepSection(title: "git worktrees", bytes: staleTotal, lines: lines)
    }

    static func caches(_ disk: Disk) -> SweepSection {
        var found: [(bytes: Int64, path: String, command: String, note: String)] = []
        let miseRoot = ("~/.local/share/mise/installs" as NSString).expandingTildeInPath
        if isDir(miseRoot) {
            let prunable = DiskParse.misePrunable(shell(["mise", "ls", "--prunable"]) ?? "")
                .map { miseRoot + "/" + $0.tool + "/" + $0.version }.filter(isDir)
            let bytes = prunable.reduce(0) { $0 + duBytes($1) }
            if bytes > 0 {
                found.append((bytes, "~/.local/share/mise", "mise prune",
                              "\(prunable.count) unused runtime versions (of \(gigabytesTrimmed(duBytes(("~/.local/share/mise" as NSString).expandingTildeInPath))) installed - only these go)"))
            }
        }
        let simRoot = ("~/Library/Developer/CoreSimulator/Devices" as NSString).expandingTildeInPath
        if isDir(simRoot) {
            let dirs = DiskParse.simulatorUDIDs(shell(["/usr/bin/xcrun", "simctl", "list", "devices", "unavailable", "-j"]) ?? "")
                .map { simRoot + "/" + $0 }.filter(isDir)
            let bytes = dirs.reduce(0) { $0 + duBytes($1) }
            if bytes > 0 {
                found.append((bytes, "~/Library/Developer/CoreSimulator/Devices", "xcrun simctl delete unavailable",
                              "\(dirs.count) unavailable devices (of \(gigabytesTrimmed(duBytes(simRoot))) all simulators - only these go)"))
            }
        }
        for entry in disk.caches {
            let path = (entry.path as NSString).expandingTildeInPath
            guard FileManager.default.fileExists(atPath: path) else { continue }
            let bytes = duBytes(path)
            if bytes >= 100_000_000 { found.append((bytes, entry.path, entry.command, entry.note)) }
        }
        var lines: [SweepLine] = []
        for f in found.sorted(by: { $0.bytes > $1.bytes }) {
            lines.append(SweepLine(label: "", detail: "  \(gigabytes(f.bytes))  \(pad(f.path, 46)) \(f.command)", command: f.command))
            if !f.note.isEmpty { lines.append(SweepLine(label: "", detail: "            " + f.note, command: nil)) }
        }
        return SweepSection(title: "caches", bytes: found.reduce(0) { $0 + $1.bytes }, lines: lines)
    }
}
