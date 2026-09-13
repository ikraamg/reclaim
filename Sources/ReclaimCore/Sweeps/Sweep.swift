import Foundation

public struct SweepLine: Equatable, Encodable {
    public var text: String
    public var command: String?
    public init(text: String, command: String?) { self.text = text; self.command = command }

    enum CodingKeys: String, CodingKey { case text, command }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(text, forKey: .text)
        try c.encode(command, forKey: .command)   // nil → null, never a missing key
    }
}

public struct SweepSection: Equatable, Encodable {
    public var title: String
    public var bytes: Int64?
    public var lines: [SweepLine]
    public init(title: String, bytes: Int64?, lines: [SweepLine]) { self.title = title; self.bytes = bytes; self.lines = lines }

    enum CodingKeys: String, CodingKey { case title, bytes, lines }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(bytes, forKey: .bytes)   // nil → null, never a missing key
        try c.encode(lines, forKey: .lines)
    }
}

public struct Sweep: Equatable, Encodable {
    public var kind: String
    public var header: [String]
    public var sections: [SweepSection]
    public var footer: [String]
    public init(kind: String, header: [String], sections: [SweepSection], footer: [String]) {
        self.kind = kind; self.header = header; self.sections = sections; self.footer = footer
    }
}

/// "%6.2fGB", decimal gigabytes like the Python's gb().
public func gigabytes(_ bytes: Int64) -> String {
    String(format: "%6.2fGB", Double(bytes) / 1_073_741_824)
}

public enum SweepReport {
    public static func text(_ s: Sweep) -> String {
        var out = s.header.joined(separator: "\n") + "\n\n"
        for section in s.sections where !section.lines.isEmpty {
            var title = section.title
            if let bytes = section.bytes { title += " - \(gigabytes(bytes).trimmingCharacters(in: .whitespaces)) reclaimable" }
            out += title + "\n" + section.lines.map(\.text).joined(separator: "\n") + "\n\n"
        }
        if !s.footer.isEmpty { out += s.footer.joined(separator: "\n") + "\n" }
        return out
    }

    public static func json(_ s: Sweep) -> String {
        jsonString(s)
    }
}
