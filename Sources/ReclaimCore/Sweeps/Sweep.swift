import Foundation

public struct SweepLine: Equatable, Encodable, Sendable {
    public var bytes: Int64?      // bytes this row is about; counted in the section total only when command is set
    public var label: String      // the thing: a path, a repo, a docker kind, a process name; "" marks a note row (detail only)
    public var detail: String     // what a human needs to know about it
    public var command: String?   // what would reclaim it; nil when nothing should
    public var nested: Bool       // indented under the previous top-level row

    public init(bytes: Int64? = nil, label: String, detail: String = "", command: String? = nil, nested: Bool = false) {
        self.bytes = bytes; self.label = label; self.detail = detail; self.command = command; self.nested = nested
    }

    enum CodingKeys: String, CodingKey { case bytes, label, detail, command, nested }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(bytes, forKey: .bytes)       // nil → null, never a missing key
        try c.encode(label, forKey: .label)
        try c.encode(detail, forKey: .detail)
        try c.encode(command, forKey: .command)
        try c.encode(nested, forKey: .nested)
    }
}

public struct SweepSection: Equatable, Encodable, Sendable {
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

public struct Sweep: Equatable, Encodable, Sendable {
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
        var out = s.header.isEmpty ? "" : s.header.joined(separator: "\n") + "\n\n"
        for section in s.sections where !section.lines.isEmpty {
            var title = section.title
            if let bytes = section.bytes { title += " - \(gigabytes(bytes).trimmingCharacters(in: .whitespaces)) reclaimable" }
            let width = min(48, section.lines.map(\.label.count).max() ?? 0)
            out += title + "\n" + section.lines.map { row($0, width: width) }.joined(separator: "\n") + "\n\n"
        }
        if !s.footer.isEmpty { out += s.footer.joined(separator: "\n") + "\n" }
        return out
    }

    static func row(_ line: SweepLine, width: Int) -> String {
        let indent = line.nested ? "    " : "  "
        var text: String
        if let bytes = line.bytes {
            text = indent + gigabytes(bytes) + "  " + pad(line.label, width) + "  " + line.detail
        } else if !line.label.isEmpty {
            text = indent + pad(line.label, width) + "  " + line.detail
        } else {
            text = "            " + line.detail
        }
        if let command = line.command { text += "   " + command }
        while text.hasSuffix(" ") { text.removeLast() }
        return text
    }

    public static func json(_ s: Sweep) -> String { jsonString(s) }
}
