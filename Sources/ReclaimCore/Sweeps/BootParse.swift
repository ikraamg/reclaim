import Foundation

public struct LaunchItem: Equatable {
    public var path: String
    public var unloadCommand: String
}

public struct OrphanedExtension: Equatable {
    public var state: String
    public var originApp: String
}

public enum BootParse {
    /// Over the threshold for long enough, hottest first, with a hint for the two repeat offenders.
    public static func cpuHogs(_ procs: [ProcessRecord], boot: Boot) -> [(ProcessRecord, hint: String)] {
        procs.filter { $0.cpu >= boot.cpuHog.percent && $0.age >= boot.cpuHog.minAgeSeconds }
            .sorted { $0.cpu > $1.cpu }
            .map { p in
                let comm = ((p.command.split(separator: " ").first.map(String.init) ?? "") as NSString).lastPathComponent
                var hint = ""
                if ["mds_stores", "mds", "mdworker_shared"].contains(comm) {
                    hint = "Spotlight indexing - exclude repo dirs: System Settings > Spotlight > Search Privacy"
                } else if p.command.contains("Shield") {
                    hint = "NordVPN Threat Protection filter - turn it off in the app"
                }
                return (p, hint)
            }
    }

    /// Non-Apple plists not prefixed by anything in `keep`, each with the launchctl line that unloads it.
    public static func launchItems(folder: String, names: [String], keep: [String]) -> [LaunchItem] {
        let expanded = (folder as NSString).expandingTildeInPath
        return names.sorted().compactMap { name in
            guard name.hasSuffix(".plist") else { return nil }
            let label = String(name.dropLast(6))
            if label.hasPrefix("com.apple.") || keep.contains(where: { label.hasPrefix($0) }) { return nil }
            let full = "'" + expanded + "/" + name + "'"
            let unload = folder.contains("Daemons") ? "sudo launchctl bootout system \(full)" : "launchctl bootout gui/$(id -u) \(full)"
            return LaunchItem(path: folder + "/" + name, unloadCommand: unload)
        }
    }

    /// `plutil -p /Library/SystemExtensions/db.plist`: an originPath line, later a state line. Orphan = app gone, not already uninstalling.
    public static func orphanedExtensions(_ plutil: String, exists: (String) -> Bool) -> [OrphanedExtension] {
        let origin = try! NSRegularExpression(pattern: #""originPath" => "([^"]+)""#)
        let state = try! NSRegularExpression(pattern: #""state" => "([^"]+)""#)
        var orphans: [OrphanedExtension] = []
        var app: String?
        for line in plutil.split(separator: "\n").map(String.init) {
            let range = NSRange(line.startIndex..., in: line)
            if let m = origin.firstMatch(in: line, range: range), let r = Range(m.range(at: 1), in: line) {
                app = String(line[r]).components(separatedBy: "/Contents/").first
            } else if let m = state.firstMatch(in: line, range: range), let r = Range(m.range(at: 1), in: line), let a = app {
                let s = String(line[r])
                if !exists(a) && !s.contains("uninstall") { orphans.append(OrphanedExtension(state: s, originApp: a)) }
                app = nil
            }
        }
        return orphans
    }

    /// `brew services list`: names whose Status column is "started".
    public static func startedServices(_ brewServices: String) -> Set<String> {
        Set(brewServices.split(separator: "\n").dropFirst().compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            return parts.count >= 2 && parts[1] == "started" ? String(parts[0]) : nil
        })
    }
}
