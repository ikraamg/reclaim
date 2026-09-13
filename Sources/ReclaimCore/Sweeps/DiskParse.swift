import Foundation

public enum VolumeKind: String { case data, rebuildable, unknown }

public struct DockerSummaryRow: Equatable {
    public var type: String, totalCount: Int, active: String, reclaimableBytes: Int64
}

public struct DockerVolume: Equatable {
    public var name: String, links: Int, bytes: Int64
}

public enum DiskParse {
    static let sizeRegex = try! NSRegularExpression(pattern: #"^([\d.]+)\s*([kMGT]?)B"#)
    static let multiplier: [String: Double] = ["": 1, "k": 1e3, "M": 1e6, "G": 1e9, "T": 1e12]

    /// Docker's decimal sizes: "1.452GB" → 1_452_000_000. Anything unparseable is 0.
    public static func size(_ raw: String) -> Int64 {
        let s = raw.trimmingCharacters(in: .whitespaces)
        guard let m = sizeRegex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let n = Range(m.range(at: 1), in: s), let value = Double(s[n]),
              let u = Range(m.range(at: 2), in: s) else { return 0 }
        return Int64((value * multiplier[String(s[u])]!).rounded())
    }

    public static func volumeKind(_ name: String, disk: Disk) -> VolumeKind {
        let low = name.lowercased()
        if disk.volumeIsData.contains(where: { low.contains($0) }) { return .data }
        if disk.volumeIsRebuildable.contains(where: { low.contains($0) }) { return .rebuildable }
        return .unknown
    }

    /// `du -sxk` lines: "<kilobytes>\t<path>".
    public static func duChildren(_ output: String) -> [String: Int64] {
        var sizes: [String: Int64] = [:]
        for line in output.split(separator: "\n") {
            let parts = line.split(maxSplits: 1, whereSeparator: { $0 == "\t" || $0 == " " })
            guard parts.count == 2, let kb = Int64(parts[0]) else { continue }
            var path = String(parts[1])
            while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
            sizes[path] = kb * 1024
        }
        return sizes
    }

    public static func duTotal(_ output: String) -> Int64 {
        output.split(separator: "\n").reduce(0) { total, line in
            total + ((Int64(line.split(whereSeparator: { $0 == "\t" || $0 == " " }).first ?? "") ?? 0) * 1024)
        }
    }

    /// `docker system df --format '{{json .}}'`: one JSON object per line, keyed here by Type.
    public static func dockerSummary(_ jsonLines: String) -> [String: DockerSummaryRow] {
        var rows: [String: DockerSummaryRow] = [:]
        for line in jsonLines.split(separator: "\n") {
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = obj["Type"] as? String else { continue }
            rows[type] = DockerSummaryRow(
                type: type,
                totalCount: Int(obj["TotalCount"] as? String ?? "") ?? 0,
                active: obj["Active"] as? String ?? "",
                reclaimableBytes: size((obj["Reclaimable"] as? String ?? "").split(separator: " ").first.map(String.init) ?? ""))
        }
        return rows
    }

    /// The VOLUME NAME table inside `docker system df -v`: name, links, size — until a line that is not three columns.
    public static func dockerVolumes(_ dfVerbose: String) -> [DockerVolume] {
        var volumes: [DockerVolume] = []
        var inTable = false
        for line in dfVerbose.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("VOLUME NAME") { inTable = true; continue }
            guard inTable else { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 3, let links = Int(parts[1]) else { inTable = false; continue }
            volumes.append(DockerVolume(name: String(parts[0]), links: links, bytes: size(String(parts[2]))))
        }
        return volumes
    }

    /// `xcrun simctl list devices unavailable -j`: every udid under devices.*[].
    public static func simulatorUDIDs(_ simctlJSON: String) -> [String] {
        guard let obj = try? JSONSerialization.jsonObject(with: Data(simctlJSON.utf8)) as? [String: Any],
              let devices = obj["devices"] as? [String: [[String: Any]]] else { return [] }
        return devices.values.flatMap { $0 }.compactMap { $0["udid"] as? String }
    }

    /// `mise ls --prunable`: "<tool> <version> ...".
    public static func misePrunable(_ output: String) -> [(tool: String, version: String)] {
        output.split(separator: "\n").compactMap { line in
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            return parts.count >= 2 ? (String(parts[0]), String(parts[1])) : nil
        }
    }
}
