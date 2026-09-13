import AppKit
import SwiftUI

/// `Reclaim --render <fixture> out.png [--dark]`: draws the popover over fixture data and exits before AppKit starts.
@MainActor
enum Render {
    static func run(_ args: [String]) -> Never {
        guard let i = args.firstIndex(of: "--render"), i + 2 < args.count, let monitor = Fixtures.monitor(named: args[i + 1]) else {
            FileHandle.standardError.write(Data("usage: Reclaim --render <\(Fixtures.names.joined(separator: "|"))> out.png [--dark]\n".utf8))
            exit(2)
        }
        let dark = args.contains("--dark")
        let renderer = ImageRenderer(content: PopoverView(monitor: monitor, scrolls: false).environment(\.colorScheme, dark ? .dark : .light))
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(3) }
        do { try png.write(to: URL(fileURLWithPath: args[i + 2])) } catch { exit(4) }
        exit(0)
    }
}
