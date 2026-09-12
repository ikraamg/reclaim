import Foundation

public enum Probe {
    /// lsof -F output: a `p<pid>` line, then `n<addr>` lines for that pid.
    public static func parseListeners(_ lsofOutput: String) -> [Int: Set<Int32>] {
        var held: [Int: Set<Int32>] = [:]
        var pid: Int32?
        for line in lsofOutput.split(separator: "\n") {
            if line.hasPrefix("p") {
                pid = Int32(line.dropFirst())
            } else if line.hasPrefix("n"), let pid, let colon = line.lastIndex(of: ":"),
                      let port = Int(line[line.index(after: colon)...]) {
                held[port, default: []].insert(pid)
            }
        }
        return held
    }

    public static func listeners() -> [Int: Set<Int32>]? {
        let table = parseListeners(shell(["lsof", "-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]))
        return table.isEmpty ? nil : table
    }

    public static func parseCwd(_ lsofOutput: String) -> String? {
        lsofOutput.split(separator: "\n").first { $0.hasPrefix("n") }.map { String($0.dropFirst()) }
    }

    public static func cwd(of pid: Int32) -> String? {
        parseCwd(shell(["lsof", "-p", String(pid), "-a", "-d", "cwd", "-Fn"]))
    }
}

public enum Worktree {
    public static func tracked(in repo: String) -> Set<String> {
        let out = shell(["git", "-C", repo, "worktree", "list", "--porcelain"])
        return Set(out.split(separator: "\n").filter { $0.hasPrefix("worktree ") }
            .map { String($0.dropFirst(9)).trimmingCharacters(in: .whitespaces) })
    }

    /// Deleted directory, or a directory git has already stopped tracking.
    public static func note(cwd: String?) -> String {
        guard let cwd else { return "" }
        var isDir: ObjCBool = false
        if !FileManager.default.fileExists(atPath: cwd, isDirectory: &isDir) || !isDir.boolValue {
            return " (its worktree \(cwd) is gone)"
        }
        guard let range = cwd.range(of: ".worktrees/") else { return "" }
        let repo = String(cwd[..<range.lowerBound])
        if FileManager.default.fileExists(atPath: repo), !tracked(in: repo).contains(cwd) {
            return " (git no longer tracks worktree \((cwd as NSString).lastPathComponent))"
        }
        return ""
    }
}
