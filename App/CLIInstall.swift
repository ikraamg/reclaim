import Foundation

/// Puts `reclaim` on PATH as a shim that runs this bundle's binary, so the CLI and the app never drift apart.
enum CLIInstall {
    static let target = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".local/bin/reclaim")

    static var executable: String { Bundle.main.executableURL?.path ?? "" }

    static func install() throws {
        let shim = "#!/bin/sh\nexec \"\(executable)\" \"$@\"\n"
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try shim.write(to: target, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: target.path)
    }

    /// What ~/.local/bin/reclaim is right now: this app, another copy, or nothing.
    static var status: String {
        guard let contents = try? String(contentsOf: target, encoding: .utf8) else {
            return FileManager.default.fileExists(atPath: target.path) ? "installed: a binary, not this app" : "not installed"
        }
        return contents.contains(executable) ? "installed: runs this app" : "installed: points elsewhere"
    }
}
