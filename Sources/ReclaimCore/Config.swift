import Foundation

public enum Evidence: String, Codable {
    case orphaned      // ppid == 1 and old enough
    case parentDead    // ppid no longer in the snapshot and old enough
    case portUnbound   // regex group 1 is a port nobody in the process family listens on
}

public struct Rule: Codable, Equatable {
    public var name: String
    public var match: String
    public var minAgeSeconds: Int
    public var evidence: Evidence

    public init(name: String, match: String, minAgeSeconds: Int, evidence: Evidence) {
        self.name = name; self.match = match; self.minAgeSeconds = minAgeSeconds; self.evidence = evidence
    }

    public static let defaults: [Rule] = [
        Rule(name: "dev-server", match: #"^puma\s[\d.]+\s\(tcp://[^:]+:(\d+)\)"#,
             minAgeSeconds: 900, evidence: .portUnbound),
        Rule(name: "busy-loop", match: #"(?:zsh|bash|sh|dash)\b.*-c\b.*while\s+(?::|true)\s*;?\s*do"#,
             minAgeSeconds: 3600, evidence: .orphaned),
        Rule(name: "file-watcher", match: #"/fsevent_watch\b"#,
             minAgeSeconds: 900, evidence: .orphaned),
        Rule(name: "mcp-server", match: #"\b(chrome-devtools-mcp|playwright-mcp|firecrawl-mcp|@playwright/mcp)\b"#,
             minAgeSeconds: 3600, evidence: .parentDead),
    ]
}

public struct Wedged: Codable, Equatable {
    public var percent: Double = 40
    public var minAgeSeconds: Int = 3600
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 40
        minAgeSeconds = try c.decodeIfPresent(Int.self, forKey: .minAgeSeconds) ?? 3600
    }
}

public enum ConfigError: Error, Equatable {
    case unreadable(URL)
    case invalid(String)
}

public struct Config: Codable, Equatable {
    public var pollSeconds = 30
    public var autoKill = false
    public var rules = Rule.defaults
    public var wedged = Wedged()
    public var neverKill = ["launchd", "kernel_task", "loginwindow", "WindowServer"]
    public var respawnsClean = ["duetexpertd", "System Events", "mdworker", "mds_stores", "sharingd"]

    public init() {}

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Config()
        pollSeconds = try c.decodeIfPresent(Int.self, forKey: .pollSeconds) ?? d.pollSeconds
        autoKill = try c.decodeIfPresent(Bool.self, forKey: .autoKill) ?? d.autoKill
        rules = try c.decodeIfPresent([Rule].self, forKey: .rules) ?? d.rules
        wedged = try c.decodeIfPresent(Wedged.self, forKey: .wedged) ?? d.wedged
        neverKill = try c.decodeIfPresent([String].self, forKey: .neverKill) ?? d.neverKill
        respawnsClean = try c.decodeIfPresent([String].self, forKey: .respawnsClean) ?? d.respawnsClean
    }

    public static let defaultURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Reclaim/config.json")

    /// Missing file is not an error: you get defaults. Unparseable file is.
    public static func load(from url: URL = defaultURL) -> Result<Config, ConfigError> {
        guard FileManager.default.fileExists(atPath: url.path) else { return .success(Config()) }
        guard let data = try? Data(contentsOf: url) else { return .failure(.unreadable(url)) }
        do {
            return .success(try JSONDecoder().decode(Config.self, from: data))
        } catch {
            return .failure(.invalid(String(describing: error)))
        }
    }

    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(self).write(to: url, options: .atomic)
    }
}
