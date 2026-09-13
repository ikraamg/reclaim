import Foundation

public enum BootSweep {
    public static func run(boot: Boot, header: String, processes: [ProcessRecord]? = nil,
                           shell: ShellRunner = realShell, fs: FileSystem = .real) -> Sweep {
        let procs = processes ?? ProcessSnapshot.live()
        return Sweep(kind: "boot",
                     header: ["boot: what starts with you and what has been burning CPU since boot  ·  \(header)",
                              "nothing below is changed automatically"],
                     sections: [cpuHogs(boot, procs), loginItems(shell), launchAgents(boot, fs), systemExtensions(shell, fs), brewLeftovers(shell, fs)],
                     footer: [])
    }

    static func cpuHogs(_ boot: Boot, _ procs: [ProcessRecord]) -> SweepSection {
        let lines = BootParse.cpuHogs(procs, boot: boot).flatMap { p, hint -> [SweepLine] in
            let comm = ((p.command.split(separator: " ").first.map(String.init) ?? "") as NSString).lastPathComponent
            var out = [SweepLine(label: comm, detail: "\(Int(p.cpu.rounded()))% CPU for \(human(age: p.age)) (pid \(p.pid))")]
            if !hint.isEmpty { out.append(SweepLine(label: "", detail: hint, nested: true)) }
            return out
        }
        return SweepSection(title: "cpu hogs (>\(Int(boot.cpuHog.percent.rounded()))% for >\(human(age: boot.cpuHog.minAgeSeconds)))", bytes: nil, lines: lines)
    }

    static func loginItems(_ shell: ShellRunner) -> SweepSection {
        let title = "login items (System Settings > General > Login Items to change)"
        guard let out = shell(["/usr/bin/osascript", "-e", "tell application \"System Events\" to get the name of every login item"], 20) else {
            return SweepSection(title: title, bytes: nil, lines: [SweepLine(label: "", detail: "could not read login items - System Events did not answer (Automation permission?)")])
        }
        let names = out.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return SweepSection(title: title, bytes: nil, lines: names.map { SweepLine(label: $0) })
    }

    static func launchAgents(_ boot: Boot, _ fs: FileSystem) -> SweepSection {
        var lines: [SweepLine] = []
        for folder in ["~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            guard let names = fs.contents(fs.expand(folder)) else { continue }
            for item in BootParse.launchItems(folder: folder, names: names, keep: boot.keep, home: fs.home) {
                lines.append(SweepLine(label: item.path, command: item.unloadCommand))
            }
        }
        return SweepSection(title: "launch agents/daemons outside boot.keep (unload, then move the plist to the Trash)", bytes: nil, lines: lines)
    }

    static func systemExtensions(_ shell: ShellRunner, _ fs: FileSystem) -> SweepSection {
        let db = shell(["/usr/bin/plutil", "-p", "/Library/SystemExtensions/db.plist"], 20) ?? ""
        let lines = BootParse.orphanedExtensions(db, exists: fs.exists).flatMap { o in
            [SweepLine(label: o.state, detail: "app gone: \(o.originApp)"),
             SweepLine(label: "", detail: "reinstall the signed app, LAUNCH it, then Finder-trash it while it runs (systemextensionsctl uninstall needs SIP off)", nested: true)]
        }
        return SweepSection(title: "orphaned system extensions", bytes: nil, lines: lines)
    }

    static func brewLeftovers(_ shell: ShellRunner, _ fs: FileSystem) -> SweepSection {
        let started = BootParse.startedServices(shell(["brew", "services", "list"], 20) ?? "")
        var lines: [SweepLine] = []
        for varDir in ["/opt/homebrew/var", "/usr/local/var"] {   // Apple silicon and Intel prefixes
            for name in (fs.contents(varDir) ?? []).sorted() where name.hasPrefix("postgresql@") && !started.contains(name) {
                let path = varDir + "/" + name
                guard let bytes = DiskSweep.duBytes(path, shell: shell) else {
                    lines.append(SweepLine(label: path, detail: "skipped - du timed out")); continue
                }
                guard bytes >= 100_000_000 else { continue }
                lines.append(SweepLine(bytes: bytes, label: path, detail: "data dir of a version that is not running", command: "rm -rf \(path)"))
            }
        }
        return SweepSection(title: "homebrew data dirs of stopped postgres versions", bytes: nil, lines: lines)
    }
}
