#if DEBUG
    import AppKit
    import SwiftUI

    /// Renders every screen with sample data in light and dark: `Wamadu --screenshots <dir>`.
    @MainActor
    enum Screenshots {
        static var outputDirectory: URL? {
            let args = CommandLine.arguments
            guard let index = args.firstIndex(of: "--screenshots"), index + 1 < args.count else { return nil }
            return URL(filePath: args[index + 1], directoryHint: .isDirectory)
        }

        static let screens: [(name: String, view: () -> AnyView)] = [
            ("checkin", { AnyView(CheckInView(onLog: { _ in })) })
        ]

        static func renderAll(to directory: URL) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for screen in screens {
                for (mode, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                    let url = directory.appending(path: "\(screen.name)-\(mode).png")
                    try render(screen.view(), appearance: NSAppearance(named: appearance)!, to: url)
                    print(url.path(percentEncoded: false))
                }
            }
        }

        // Glass is composited by the window server and cannot be captured offscreen, the panel background stands in.
        private static func render(_ view: AnyView, appearance: NSAppearance, to url: URL) throws {
            let hosting = NSHostingView(
                rootView: view.background(Color(nsColor: .windowBackgroundColor)).clipShape(.rect(cornerRadius: 16)))
            hosting.appearance = appearance
            hosting.frame.size = hosting.fittingSize
            let window = CheckInPanel()
            window.setContentSize(hosting.frame.size)
            window.appearance = appearance
            window.contentView = hosting
            window.setFrameOrigin(NSPoint(x: -10_000, y: -10_000))
            window.makeKeyAndOrderFront(nil)
            hosting.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.3))
            guard let rep = hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
            hosting.cacheDisplay(in: hosting.bounds, to: rep)
            window.orderOut(nil)
            guard let png = rep.representation(using: .png, properties: [:]) else {
                throw CocoaError(.fileWriteUnknown, userInfo: [NSFilePathErrorKey: url.path])
            }
            try png.write(to: url)
        }
    }
#endif
