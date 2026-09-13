import SwiftUI
import ReclaimCore

struct FindingRow: View {
    let finding: Finding
    let action: String?
    let killable: Bool
    let kill: (Int32) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(finding.process.command)
                    .font(Theme.labelMedium)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .help(finding.process.command)
                Text(numbers)
                    .font(Theme.mono)
                    .foregroundStyle(.secondary)
                Text(finding.reason)
                    .font(Theme.secondary)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            if let action {
                Text(action).font(Theme.mono).foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: 110, alignment: .trailing)
            } else if killable {
                KillButton(label: "Kill") { kill(finding.process.pid) }
            }
        }
        .padding(.vertical, 8)
    }

    var numbers: String {
        let p = finding.process
        return padded(String(p.pid), 6) + " " + padded(finding.category, 11) + " " + padded(human(age: p.age), 7)
            + String(format: " %5dMB %5.1f%%", p.rssKB / 1024, p.cpu)
    }

    func padded(_ s: String, _ width: Int) -> String {
        s.count >= width ? s : s + String(repeating: " ", count: width - s.count)
    }
}
