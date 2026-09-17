import AppKit
import SwiftUI

/// `Reclaim --render <fixture> out.png [--dark]`: draws the popover or the sweeps window over fixture data.
@MainActor
enum Render {
    static func run(_ args: [String]) -> Never {
        guard let i = args.firstIndex(of: "--render"), i + 2 < args.count else { usage() }
        let dark = args.contains("--dark")
        let scheme: ColorScheme = dark ? .dark : .light
        let renderer: ImageRenderer<AnyView>
        if let monitor = Fixtures.monitor(named: args[i + 1]) {
            renderer = ImageRenderer(content: AnyView(PopoverView(monitor: monitor, scrolls: false).environment(\.colorScheme, scheme)))
        } else if let sweeps = Fixtures.sweeps(named: args[i + 1]) {
            renderer = ImageRenderer(content: AnyView(SweepsView(sweeps: sweeps, scrolls: false)
                .environment(\.colorScheme, scheme)
                .environment(\.timeZone, TimeZone(identifier: "UTC")!)))
        } else {
            usage()
        }
        renderer.scale = 2
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(3) }
        do { try png.write(to: URL(fileURLWithPath: args[i + 2])) } catch { exit(4) }
        exit(0)
    }

    private static func usage() -> Never {
        FileHandle.standardError.write(Data("usage: Reclaim --render <\(Fixtures.names.joined(separator: "|"))> out.png [--dark]\n".utf8))
        exit(2)
    }
}
