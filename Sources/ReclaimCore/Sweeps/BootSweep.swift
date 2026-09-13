import Foundation

public enum BootSweep {
    public static func run(boot: Boot, header: String) -> Sweep {
        Sweep(kind: "boot",
              header: ["boot: what starts with you and what has been burning CPU since boot  ·  \(header)",
                       "nothing below is changed automatically"],
              sections: [cpuHogs(boot), loginItems(), launchAgents(boot), systemExtensions(), brewLeftovers()],
              footer: [])
    }

    static func cpuHogs(_ boot: Boot) -> SweepSection {
        let lines = BootParse.cpuHogs(ProcessSnapshot.live(), boot: boot).flatMap { p, hint -> [SweepLine] in
            let comm = ((p.command.split(separator: " ").first.map(String.init) ?? "") as NSString).lastPathComponent
            var out = [SweepLine(text: "  \(pad(String(p.pid), 6)) \(String(format: "%5.0f", p.cpu))%cpu  \(pad(human(age: p.age), 8)) \(comm)", command: nil)]
            if !hint.isEmpty { out.append(SweepLine(text: "            " + hint, command: nil)) }
            return out
        }
        return SweepSection(title: "cpu hogs (>\(Int(boot.cpuHog.percent))% for >\(human(age: boot.cpuHog.minAgeSeconds)))", bytes: nil, lines: lines)
    }

    static func loginItems() -> SweepSection {
        let out = shell(["/usr/bin/osascript", "-e", "tell application \"System Events\" to get the name of every login item"]) ?? ""
        let names = out.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return SweepSection(title: "login items (System Settings > General > Login Items to change)", bytes: nil,
                            lines: names.map { SweepLine(text: "  " + $0, command: nil) })
    }

    static func launchAgents(_ boot: Boot) -> SweepSection {
        var lines: [SweepLine] = []
        for folder in ["~/Library/LaunchAgents", "/Library/LaunchAgents", "/Library/LaunchDaemons"] {
            let path = (folder as NSString).expandingTildeInPath
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: path) else { continue }
            for item in BootParse.launchItems(folder: folder, names: names, keep: boot.keep) {
                lines.append(SweepLine(text: "  \(pad(item.path, 62)) \(item.unloadCommand)", command: item.unloadCommand))
            }
        }
        return SweepSection(title: "launch agents/daemons outside boot.keep (unload, then move the plist to the Trash)", bytes: nil, lines: lines)
    }

    static func systemExtensions() -> SweepSection {
        let db = shell(["/usr/bin/plutil", "-p", "/Library/SystemExtensions/db.plist"]) ?? ""
        let lines = BootParse.orphanedExtensions(db) { FileManager.default.fileExists(atPath: $0) }.flatMap { o in
            [SweepLine(text: "  \(pad(o.state, 22)) app gone: \(o.originApp)", command: nil),
             SweepLine(text: "            reinstall the signed app, LAUNCH it, then Finder-trash it while it runs (systemextensionsctl uninstall needs SIP off)", command: nil)]
        }
        return SweepSection(title: "orphaned system extensions", bytes: nil, lines: lines)
    }

    static func brewLeftovers() -> SweepSection {
        let started = BootParse.startedServices(shell(["brew", "services", "list"]) ?? "")
        let varDir = "/opt/homebrew/var"
        let names = ((try? FileManager.default.contentsOfDirectory(atPath: varDir)) ?? []).sorted()
        var lines: [SweepLine] = []
        for name in names where name.hasPrefix("postgresql@") && !started.contains(name) {
            let path = varDir + "/" + name
            let bytes = DiskSweep.duBytes(path)
            guard bytes >= 100_000_000 else { continue }
            let cmd = "rm -rf \(path)"
            lines.append(SweepLine(text: "  \(gigabytes(bytes))  \(pad(path, 40)) \(cmd)   (data dir of a version that is not running)", command: cmd))
        }
        return SweepSection(title: "homebrew data dirs of stopped postgres versions", bytes: nil, lines: lines)
    }
}
