import SwiftUI
import ReclaimCore

struct PopoverActions {
    var kill: (Int32) -> Void = { _ in }
    var killAll: () -> Void = {}
    var settings: () -> Void = {}
    var quit: () -> Void = {}
}

struct PopoverView: View {
    let monitor: Monitor
    var actions = PopoverActions()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let banner = monitor.banner {
                Text(banner)
                    .font(Theme.labelMedium)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
            }
            Text(monitor.header)
                .font(Theme.mono)
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            Hairline()
            content
                .frame(maxHeight: 480, alignment: .top)
                .clipped()
            Hairline()
            footer
        }
        .frame(width: Theme.popoverWidth)
        .background(.background)
    }

    @ViewBuilder var content: some View {
        if monitor.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nothing to reclaim.").font(Theme.labelMedium)
                Text(monitor.emptyDetail).font(Theme.secondary).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.vertical, 24)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                if !monitor.killRows.isEmpty {
                    group(title: "\(monitor.killTitle) \(monitor.killRows.count)", rows: monitor.killRows, killAll: monitor.showsKillAll)
                }
                if !monitor.reportRows.isEmpty {
                    if !monitor.killRows.isEmpty { Hairline() }
                    group(title: "REPORTED \(monitor.reportRows.count) · your call", rows: monitor.reportRows, killAll: false)
                }
                if let title = monitor.hogsTitle {
                    if !monitor.findings.isEmpty { Hairline() }
                    hogs(title: title)
                }
            }
        }
    }

    func group(title: String, rows: [Finding], killAll: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text(title).font(Theme.groupTitle)
                Spacer()
                if killAll { KillButton(label: "Kill all") { actions.killAll() } }
            }
            .padding(.top, 12)
            .padding(.bottom, 2)
            ForEach(Array(rows.enumerated()), id: \.element.process.pid) { index, row in
                if index > 0 { Hairline().opacity(0.6) }
                FindingRow(finding: row, action: monitor.action(for: row.process.pid),
                           killable: Monitor.canKill(row), kill: actions.kill)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 4)
    }

    func hogs(title: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(Theme.groupTitle).padding(.top, 12)
            ForEach(monitor.hogs, id: \.pid) { p in
                HStack(spacing: 8) {
                    Text(String(format: "%6d %6.1fGB", p.pid, Double(p.rssKB) / 1_048_576)).font(Theme.mono).foregroundStyle(.secondary)
                    Text(p.command).font(Theme.secondary).lineLimit(1).truncationMode(.middle)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
    }

    var footer: some View {
        HStack {
            Text(monitor.footer).font(Theme.mono).foregroundStyle(.secondary)
            Spacer()
            Button("Settings") { actions.settings() }.buttonStyle(.plain).font(Theme.secondary)
            Button("Quit") { actions.quit() }.buttonStyle(.plain).font(Theme.secondary).padding(.leading, 12)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}
