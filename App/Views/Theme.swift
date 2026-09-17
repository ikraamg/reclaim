import SwiftUI

enum Theme {
    static let popoverWidth: CGFloat = 400
    static let sweepsWidth: CGFloat = 560
    static let labelMedium = Font.system(.body).weight(.medium)
    static let secondary = Font.system(.callout)
    static let mono = Font.system(.callout, design: .monospaced)
    static let groupTitle = Font.system(.callout).weight(.bold)
    static let title = Font.system(.body).weight(.bold)
    static let hairline = Color.primary.opacity(0.18)
}

struct Hairline: View {
    var body: some View { Rectangle().fill(Theme.hairline).frame(height: 1) }
}

/// Text in a hairline box: the only button chrome in the popover.
struct BoxButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(Theme.secondary.weight(.medium))
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .stroke(Color.primary.opacity(configuration.isPressed ? 1 : 0.5), lineWidth: 1))
            .contentShape(Rectangle())
    }
}

/// First click arms it for three seconds, the second click confirms.
struct KillButton: View {
    let label: String
    let confirm: () -> Void
    @State private var armed = false
    @State private var disarm: Task<Void, Never>?

    var body: some View {
        Button(armed ? "Sure?" : label) {
            disarm?.cancel()
            if armed {
                armed = false
                confirm()
            } else {
                armed = true
                disarm = Task {
                    try? await Task.sleep(for: .seconds(3))
                    if !Task.isCancelled { armed = false }
                }
            }
        }
        .buttonStyle(BoxButtonStyle())
    }
}
