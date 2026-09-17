import SwiftUI
import ReclaimCore

struct SweepsActions {
    var run: () -> Void = {}
    var copy: (String) -> Void = { _ in }
}

/// Disk above Boot, one page. Every command is shown and copyable; nothing in this view can run one.
struct SweepsView: View {
    let sweeps: Sweeps
    var actions = SweepsActions()
    var scrolls = true
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if scrolls {
                ScrollView { content }.frame(minHeight: 240, maxHeight: 720)
            } else {
                content
            }
            Hairline()
            footer
        }
        .frame(width: Theme.sweepsWidth)
        .background(.background)
    }

    var content: some View {
        VStack(alignment: .leading, spacing: 0) {
            block(title: "DISK", sweep: sweeps.disk, running: sweeps.running.contains("disk"))
            block(title: "BOOT", sweep: sweeps.boot, running: sweeps.running.contains("boot"))
        }
    }

    @ViewBuilder func block(title: String, sweep: Sweep?, running: Bool) -> some View {
        if sweep != nil || running {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(title).font(Theme.title)
                    if running { Text("running…").font(Theme.secondary).foregroundStyle(.secondary) }
                }
                if let sweep {
                    let gutter = sweep.sections.contains { $0.lines.contains { $0.bytes != nil } }   // boot has no sizes
                    lines(sweep.header)
                    ForEach(Array(sweep.sections.enumerated()), id: \.offset) { _, section in
                        if !section.lines.isEmpty { self.section(section, gutter: gutter) }
                    }
                    lines(sweep.footer)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    @ViewBuilder func lines(_ lines: [String]) -> some View {
        if !lines.isEmpty {
            Text(lines.joined(separator: "\n"))
                .font(Theme.mono)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    func section(_ s: SweepSection, gutter: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Hairline().opacity(0.6).padding(.top, 4)
            Text(s.bytes.map { "\(s.title) · \(gigabytes($0).trimmingCharacters(in: .whitespaces)) reclaimable" } ?? s.title)
                .font(Theme.groupTitle)
                .padding(.top, 6)
            ForEach(Array(s.lines.enumerated()), id: \.offset) { _, line in row(line, gutter: gutter) }
        }
    }

    func row(_ line: SweepLine, gutter: Bool) -> some View {
        HStack(alignment: .top, spacing: 8) {
            if gutter {
                Text(line.bytes.map { gigabytes($0) } ?? "")
                    .font(Theme.mono)
                    .foregroundStyle(.secondary)
                    .frame(width: 64, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 2) {
                if !line.label.isEmpty {
                    Text(line.label).font(Theme.labelMedium).lineLimit(1).truncationMode(.middle).help(line.label)
                }
                if !line.detail.isEmpty {
                    Text(line.detail).font(Theme.secondary).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let command = line.command {
                    HStack(alignment: .top, spacing: 8) {
                        Text(command).font(Theme.mono).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                        CopyButton { actions.copy(command) }
                    }
                }
            }
        }
        .padding(.leading, line.nested ? 16 : 0)
        .padding(.vertical, 3)
    }

    var footer: some View {
        HStack {
            footerText.font(Theme.mono).foregroundStyle(.secondary)
            Spacer()
            Button("Run again") { actions.run() }
                .buttonStyle(.plain)
                .font(Theme.secondary)
                .disabled(sweeps.isRunning)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    var footerText: Text {
        if sweeps.isRunning { return Text("running…") }
        guard let ranAt = sweeps.ranAt, let seconds = sweeps.seconds else { return Text("not run yet") }
        let f = DateFormatter()
        f.timeZone = timeZone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "HH:mm"   // as the popover footer
        return Text("ran \(f.string(from: ranAt)) · \(seconds)s")
    }
}

/// "Copy" reads "Copied" for two seconds. It hands the command to `copy` and nothing else.
struct CopyButton: View {
    let copy: () -> Void
    @State private var copied = false
    @State private var reset: Task<Void, Never>?

    var body: some View {
        Button(copied ? "Copied" : "Copy") {
            copy()
            copied = true
            reset?.cancel()
            reset = Task {
                try? await Task.sleep(for: .seconds(2))
                if !Task.isCancelled { copied = false }
            }
        }
        .buttonStyle(BoxButtonStyle())
    }
}
