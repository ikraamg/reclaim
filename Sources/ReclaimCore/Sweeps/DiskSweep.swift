import Foundation

public enum DiskSweep {
    static func shellQuoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }
    static func gigabytesTrimmed(_ bytes: Int64) -> String { gigabytes(bytes).trimmingCharacters(in: .whitespaces) }

    /// nil when du did not answer in time — callers say "skipped" instead of showing a smaller number.
    static func duBytes(_ path: String, shell: ShellRunner) -> Int64? {
        shell(["/usr/bin/du", "-sxk", path], 60).map(DiskParse.duTotal)
    }

    public static func run(disk: Disk, shell: ShellRunner = realShell, fs: FileSystem = .real, now: Date = Date()) -> Sweep {
        var header: [String] = []
        let df = (shell(["/bin/df", "-g", "/System/Volumes/Data"], 20) ?? "").split(separator: "\n")
        if df.count > 1 {
            let f = df[1].split(separator: " ", omittingEmptySubsequences: true)
            if f.count > 4 { header.append("disk: \(f[2])GB used, \(f[3])GB free (\(f[4]) full)  ·  nothing below is deleted automatically") }
        }
        var sections = [docker(disk, shell), worktrees(disk, shell, fs, now), caches(disk, shell, fs)]
        sections.sort { ($0.bytes ?? 0) > ($1.bytes ?? 0) }
        var footer = ["total reclaimable: \(gigabytesTrimmed(sections.reduce(0) { $0 + ($1.bytes ?? 0) }))"]
        if !(shell(["sh", "-c", "command -v mo"], 20) ?? "").isEmpty {
            footer.append("not counted above, mole owns these (interactive, both take --dry-run):")
            footer.append("  mo clean    caches this table misses - app leftovers, iOS backups, conda, maven")
            footer.append("  mo purge    node_modules/dist/target/Pods across every repo in ~/.config/mole/purge_paths")
        }
        return Sweep(kind: "disk", header: header, sections: sections, footer: footer)
    }

    static func docker(_ disk: Disk, _ shell: ShellRunner) -> SweepSection {
        guard !(shell(["sh", "-c", "command -v docker"], 20) ?? "").isEmpty else { return SweepSection(title: "docker", bytes: 0, lines: []) }
        let summary = DiskParse.dockerSummary(shell(["docker", "system", "df", "--format", "{{json .}}"], 20) ?? "")
        guard !summary.isEmpty else {
            return SweepSection(title: "docker", bytes: 0, lines: [SweepLine(label: "", detail: "docker is installed but not running")])
        }
        var lines: [SweepLine] = []
        var total: Int64 = 0
        for (kind, label, cmd) in [("Images", "images", "docker image prune -a"), ("Containers", "containers", "docker container prune"), ("Build Cache", "build cache", "docker builder prune")] {
            guard let row = summary[kind], row.reclaimableBytes > 100_000_000 else { continue }
            total += row.reclaimableBytes
            lines.append(SweepLine(bytes: row.reclaimableBytes, label: label, detail: "\(row.totalCount) total, \(row.active) active", command: cmd))
        }
        let volumes = DiskParse.dockerVolumes(shell(["docker", "system", "df", "-v"], 20) ?? "")
        let byKind = Dictionary(grouping: volumes) { DiskParse.volumeKind($0.name, disk: disk) }
        let free = (byKind[.rebuildable] ?? []).filter { $0.links == 0 }
        if !free.isEmpty {
            let size = free.reduce(0) { $0 + $1.bytes }
            total += size
            let names = free.map(\.name).sorted()
            lines.append(SweepLine(bytes: size, label: "volumes", detail: "\(free.count) unused and rebuildable",
                                   command: "docker volume rm " + names.joined(separator: " ")))
        }
        if let data = byKind[.data], !data.isEmpty {
            let names = data.map(\.name).sorted().prefix(3).joined(separator: ", ")
            lines.append(SweepLine(bytes: data.reduce(0) { $0 + $1.bytes }, label: "volumes",
                                   detail: "\(data.count) look like data (\(names)) - leave alone, never `docker volume prune`"))
        }
        let unknown = (byKind[.unknown] ?? []).filter { $0.links == 0 && $0.bytes > 100_000_000 }
        if !unknown.isEmpty {
            lines.append(SweepLine(bytes: unknown.reduce(0) { $0 + $1.bytes }, label: "volumes",
                                   detail: "\(unknown.count) unnamed and unclassified - `docker volume inspect` before deleting"))
        }
        return SweepSection(title: "docker", bytes: total, lines: lines)
    }

    static func worktrees(_ disk: Disk, _ shell: ShellRunner, _ fs: FileSystem, _ now: Date) -> SweepSection {
        var lines: [SweepLine] = []
        var staleTotal: Int64 = 0
        let root = fs.expand(disk.worktreeRoot)
        let roots = (fs.contents(root) ?? []).filter { $0.hasSuffix(".worktrees") }.sorted().map { root + "/" + $0 }
        for worktreeRoot in roots {
            guard let du = shell(["sh", "-c", "/usr/bin/du -sxk \(shellQuoted(worktreeRoot))/*/ 2>/dev/null"], 120) else {
                lines.append(SweepLine(label: fs.tilde(worktreeRoot), detail: "skipped - du timed out"))
                continue
            }
            let sizes = DiskParse.duChildren(du)
            if sizes.isEmpty { continue }
            let repoName = (worktreeRoot as NSString).lastPathComponent.replacingOccurrences(of: ".worktrees", with: "")
            let repo = (worktreeRoot as NSString).deletingLastPathComponent + "/" + repoName
            guard let porcelain = shell(["git", "-C", repo, "worktree", "list", "--porcelain"], 20) else {
                lines.append(SweepLine(label: repoName, detail: "skipped - git did not answer")); continue
            }
            let tracked = Worktree.parseTracked(porcelain)
            var stale: [(bytes: Int64, path: String, days: Double, tracked: Bool)] = []
            for (path, bytes) in sizes {
                let raw = (shell(["git", "-C", path, "log", "-1", "--format=%ct"], 20) ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                let days = Double(raw).map { (now.timeIntervalSince1970 - $0) / 86400 } ?? 0
                guard let status = shell(["git", "-C", path, "status", "--porcelain"], 20) else { continue }   // unknown → not stale
                let dirty = !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                if !dirty && days > Double(disk.worktreeStaleDays) { stale.append((bytes, path, days, tracked.contains(path))) }
            }
            let total = sizes.values.reduce(0, +)
            let staleBytes = stale.reduce(0) { $0 + $1.bytes }
            staleTotal += staleBytes
            lines.append(SweepLine(bytes: total, label: repoName,
                                   detail: "\(sizes.count) worktrees, \(stale.count) clean and untouched for \(disk.worktreeStaleDays)+ days (\(gigabytesTrimmed(staleBytes)))"))
            for s in stale.sorted(by: { $0.bytes != $1.bytes ? $0.bytes > $1.bytes : $0.path > $1.path }).prefix(5) {
                let name = (s.path as NSString).lastPathComponent
                let cmd = s.tracked ? "git -C \(shellQuoted(repo)) worktree remove \(shellQuoted(s.path))" : "rm -rf \(shellQuoted(s.path))"
                lines.append(SweepLine(bytes: s.bytes, label: name, detail: "\(Int(s.days))d, \(s.tracked ? "tracked" : "untracked by git")", command: cmd, nested: true))
            }
            let globs = disk.regenerableInRepo.map { "\(shellQuoted(worktreeRoot))/*/\($0)" }.joined(separator: " ")
            let junk = shell(["sh", "-c", "/usr/bin/du -sxk \(globs) 2>/dev/null"], 120).map(DiskParse.duTotal) ?? 0
            if junk > 200_000_000 {
                staleTotal += junk
                lines.append(SweepLine(bytes: junk, label: disk.regenerableInRepo.joined(separator: "/"), detail: "inside worktrees you still use",
                                       command: "rm -rf \(fs.tilde(worktreeRoot))/*/{\(disk.regenerableInRepo.joined(separator: ","))}", nested: true))
            }
        }
        if !lines.isEmpty {
            lines.append(SweepLine(label: "", detail: "check each one first - a worktree is unpushed work until proven otherwise"))
        }
        return SweepSection(title: "git worktrees", bytes: staleTotal, lines: lines)
    }

    static func caches(_ disk: Disk, _ shell: ShellRunner, _ fs: FileSystem) -> SweepSection {
        var lines: [SweepLine] = []
        var total: Int64 = 0
        func add(_ bytes: Int64, _ label: String, _ detail: String, _ command: String) {
            total += bytes
            lines.append(SweepLine(bytes: bytes, label: label, detail: detail, command: command))
        }
        let miseRoot = fs.expand("~/.local/share/mise/installs")
        if fs.isDirectory(miseRoot) {
            let prunable = DiskParse.misePrunable(shell(["mise", "ls", "--prunable"], 20) ?? "")
                .map { miseRoot + "/" + $0.tool + "/" + $0.version }.filter(fs.isDirectory)
            let bytes = prunable.compactMap { duBytes($0, shell: shell) }.reduce(0, +)
            if bytes > 0 {
                let all = duBytes(fs.expand("~/.local/share/mise"), shell: shell).map(gigabytesTrimmed) ?? "?"
                add(bytes, "~/.local/share/mise", "\(prunable.count) unused runtime versions (of \(all) installed - only these go)", "mise prune")
            }
        }
        let simRoot = fs.expand("~/Library/Developer/CoreSimulator/Devices")
        if fs.isDirectory(simRoot) {
            let dirs = DiskParse.simulatorUDIDs(shell(["/usr/bin/xcrun", "simctl", "list", "devices", "unavailable", "-j"], 20) ?? "")
                .map { simRoot + "/" + $0 }.filter(fs.isDirectory)
            let bytes = dirs.compactMap { duBytes($0, shell: shell) }.reduce(0, +)
            if bytes > 0 {
                let all = duBytes(simRoot, shell: shell).map(gigabytesTrimmed) ?? "?"
                add(bytes, "~/Library/Developer/CoreSimulator/Devices", "\(dirs.count) unavailable devices (of \(all) all simulators - only these go)", "xcrun simctl delete unavailable")
            }
        }
        for entry in disk.caches {
            let path = fs.expand(entry.path)
            guard fs.exists(path) else { continue }
            guard let bytes = duBytes(path, shell: shell) else {
                lines.append(SweepLine(label: entry.path, detail: "skipped - du timed out"))
                continue
            }
            if bytes >= 100_000_000 { add(bytes, entry.path, entry.note, entry.command) }
        }
        lines.sort { ($0.bytes ?? -1) != ($1.bytes ?? -1) ? ($0.bytes ?? -1) > ($1.bytes ?? -1) : $0.label < $1.label }
        return SweepSection(title: "caches", bytes: total, lines: lines)
    }
}
