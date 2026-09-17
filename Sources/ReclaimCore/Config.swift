import Foundation

public enum Evidence: String, Codable, Sendable {
    case orphaned      // ppid == 1 and old enough
    case portUnbound   // regex group 1 is a port nobody in the process family listens on
}

public struct Rule: Codable, Equatable, Sendable {
    public var name: String
    public var match: String
    public var minAgeSeconds: Int
    public var evidence: Evidence
    public var minCPU: Double?

    public init(name: String, match: String, minAgeSeconds: Int, evidence: Evidence, minCPU: Double? = nil) {
        self.name = name; self.match = match; self.minAgeSeconds = minAgeSeconds; self.evidence = evidence
        self.minCPU = minCPU
    }

    public static let defaults: [Rule] = [
        Rule(name: "dev-server", match: #"^puma\s[\d.]+\s\(tcp://[^:]+:(\d+)\)"#,
             minAgeSeconds: 900, evidence: .portUnbound),
        Rule(name: "busy-loop", match: #"(?:zsh|bash|sh|dash)\b.*-c\b.*while\s+(?::|true)\s*;?\s*do"#,
             minAgeSeconds: 3600, evidence: .orphaned, minCPU: 20),
        Rule(name: "file-watcher", match: #"/fsevent_watch\b"#,
             minAgeSeconds: 900, evidence: .orphaned),
        Rule(name: "mcp-server", match: #"\b(chrome-devtools-mcp|playwright-mcp|firecrawl-mcp|@playwright/mcp)\b"#,
             minAgeSeconds: 3600, evidence: .orphaned),
    ]
}

public struct Wedged: Codable, Equatable, Sendable {
    public var percent: Double = 40
    public var minAgeSeconds: Int = 3600
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 40
        minAgeSeconds = try c.decodeIfPresent(Int.self, forKey: .minAgeSeconds) ?? 3600
    }
}

public struct CacheEntry: Codable, Equatable, Sendable {
    public var path: String, command: String, note: String
    public init(path: String, command: String, note: String) { self.path = path; self.command = command; self.note = note }

    // Rebuilt or re-downloaded on demand. Nothing here is deleted automatically.
    public static let defaults: [CacheEntry] = [
        CacheEntry(path: "~/Library/Developer/Xcode/DerivedData", command: "rm -rf ~/Library/Developer/Xcode/DerivedData/*", note: "rebuilt on next build"),
        CacheEntry(path: "~/Library/Developer/Xcode/iOS DeviceSupport", command: "rm -rf ~/Library/Developer/Xcode/'iOS DeviceSupport'/*", note: "old iOS symbols"),
        CacheEntry(path: "~/.npm/_cacache", command: "npm cache clean --force", note: "re-downloaded on demand"),
        CacheEntry(path: "~/.npm/_npx", command: "rm -rf ~/.npm/_npx", note: "npx cache - stop MCP servers first"),
        CacheEntry(path: "~/.cache/uv", command: "uv cache clean", note: "python wheels - prune only drops unused, clean takes the lot"),
        CacheEntry(path: "~/Library/Caches/Yarn", command: "yarn cache clean", note: ""),
        CacheEntry(path: "~/Library/Caches/Homebrew", command: "brew cleanup -s", note: "downloaded bottles"),
        CacheEntry(path: "~/Library/pnpm", command: "pnpm store prune", note: ""),
        CacheEntry(path: "~/Library/Caches/pip", command: "pip cache purge", note: ""),
        CacheEntry(path: "~/Library/Caches/go-build", command: "go clean -cache", note: ""),
        CacheEntry(path: "~/.Trash", command: "rm -rf ~/.Trash/*", note: "Trash"),
    ]
}

public struct CPUHog: Codable, Equatable, Sendable {
    public var percent: Double = 50
    public var minAgeSeconds: Int = 1800
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 50
        minAgeSeconds = try c.decodeIfPresent(Int.self, forKey: .minAgeSeconds) ?? 1800
    }
}

public struct Boot: Codable, Equatable, Sendable {
    // Launch agents/daemons already said yes to; anything else non-Apple is listed.
    public var keep = ["homebrew.mxcl.", "com.grammarly.", "com.ikraam.", "com.logi.optionsplus",
                       "com.docker.", "com.nordvpn.macos.helper", "us.zoom.ZoomDaemon"]
    public var cpuHog = CPUHog()
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Boot()
        keep = try c.decodeIfPresent([String].self, forKey: .keep) ?? d.keep
        cpuHog = try c.decodeIfPresent(CPUHog.self, forKey: .cpuHog) ?? d.cpuHog
    }
}

public struct Disk: Codable, Equatable, Sendable {
    public var worktreeRoot = "~/Documents/GitHub"
    public var worktreeStaleDays = 21
    public var regenerableInRepo = ["tmp", "log", "node_modules", "coverage"]
    // A docker volume named like data is somebody's database.
    public var volumeIsData = ["_data", "_db", "pgdata", "postgres", "mysql", "mariadb", "redis",
                               "clickhouse", "minio", "storage", "esdata", "elastic"]
    public var volumeIsRebuildable = ["node_modules", "bundle", "_cache", "cache_", "tmp", "build",
                                      "public_assets", "assets"]
    public var caches = CacheEntry.defaults
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Disk()
        worktreeRoot = try c.decodeIfPresent(String.self, forKey: .worktreeRoot) ?? d.worktreeRoot
        worktreeStaleDays = try c.decodeIfPresent(Int.self, forKey: .worktreeStaleDays) ?? d.worktreeStaleDays
        regenerableInRepo = try c.decodeIfPresent([String].self, forKey: .regenerableInRepo) ?? d.regenerableInRepo
        volumeIsData = try c.decodeIfPresent([String].self, forKey: .volumeIsData) ?? d.volumeIsData
        volumeIsRebuildable = try c.decodeIfPresent([String].self, forKey: .volumeIsRebuildable) ?? d.volumeIsRebuildable
        caches = try c.decodeIfPresent([CacheEntry].self, forKey: .caches) ?? d.caches
    }
}

public struct CPUAlert: Codable, Equatable, Sendable {
    public var percent: Double = 50
    public var minutes: Int = 30
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        percent = try c.decodeIfPresent(Double.self, forKey: .percent) ?? 50
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 30
    }
}

public struct MemoryAlert: Codable, Equatable, Sendable {
    public var gigabytes: Double = 4
    public var minutes: Int = 10
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        gigabytes = try c.decodeIfPresent(Double.self, forKey: .gigabytes) ?? 4
        minutes = try c.decodeIfPresent(Int.self, forKey: .minutes) ?? 10
    }
}

public struct Alerts: Codable, Equatable, Sendable {
    public var notify = true
    public var cpu = CPUAlert()
    public var memory = MemoryAlert()
    public var swapPercent: Double = 80
    public var thermal = true
    public var batteryDrainPerHour: Double = 20
    public init() {}
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Alerts()
        notify = try c.decodeIfPresent(Bool.self, forKey: .notify) ?? d.notify
        cpu = try c.decodeIfPresent(CPUAlert.self, forKey: .cpu) ?? d.cpu
        memory = try c.decodeIfPresent(MemoryAlert.self, forKey: .memory) ?? d.memory
        swapPercent = try c.decodeIfPresent(Double.self, forKey: .swapPercent) ?? d.swapPercent
        thermal = try c.decodeIfPresent(Bool.self, forKey: .thermal) ?? d.thermal
        batteryDrainPerHour = try c.decodeIfPresent(Double.self, forKey: .batteryDrainPerHour) ?? d.batteryDrainPerHour
    }
}

public enum ConfigError: Error, Equatable {
    case unreadable(URL)
    case invalid(String)
}

public struct Config: Codable, Equatable, Sendable {
    public var pollSeconds = 30
    public var autoKill = false
    public var rules = Rule.defaults
    public var wedged = Wedged()
    public var neverKill = ["launchd", "kernel_task", "loginwindow", "WindowServer"]
    public var respawnsClean = ["duetexpertd", "System Events", "mdworker", "mds_stores", "sharingd"]
    public var busyByDesign = ["fileproviderd": "iCloud Drive or another file provider is syncing, let it finish"]
    public var boot = Boot()
    public var disk = Disk()
    public var alerts = Alerts()

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
        busyByDesign = try c.decodeIfPresent([String: String].self, forKey: .busyByDesign) ?? d.busyByDesign
        boot = try c.decodeIfPresent(Boot.self, forKey: .boot) ?? d.boot
        disk = try c.decodeIfPresent(Disk.self, forKey: .disk) ?? d.disk
        alerts = try c.decodeIfPresent(Alerts.self, forKey: .alerts) ?? d.alerts
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

    /// Writes the known keys over whatever is already in the file, so a hand-added key survives a Settings save.
    public func save(to url: URL = defaultURL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var merged = (try? JSONSerialization.jsonObject(with: Data(contentsOf: url))) as? [String: Any] ?? [:]
        let known = try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as? [String: Any] ?? [:]
        for (key, value) in known {
            if var section = merged[key] as? [String: Any], let updates = value as? [String: Any] {
                updates.forEach { section[$0] = $1 }
                merged[key] = section
            } else {
                merged[key] = value
            }
        }
        let data = try JSONSerialization.data(withJSONObject: merged, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try data.write(to: url, options: .atomic)
    }
}
