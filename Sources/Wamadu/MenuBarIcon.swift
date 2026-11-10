import AppKit
import WamaduCore

/// The three time block bars as a template image, one look per tracker mode.
enum MenuBarIcon {
    static func image(for mode: TrackerMode) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { _ in
            let bars = NSBezierPath()
            for rect in [
                NSRect(x: 1.6, y: 2.6, width: 10.8, height: 3.4),
                NSRect(x: 5.6, y: 7.3, width: 10.8, height: 3.4),
                NSRect(x: 1.6, y: 12, width: 8, height: 3.4),
            ] {
                bars.append(NSBezierPath(roundedRect: rect, xRadius: 1.7, yRadius: 1.7))
            }
            // template images only use alpha, the system picks the color
            NSColor.black.withAlphaComponent(mode == .off ? 0.4 : 1).set()
            if mode == .onBreak {
                bars.lineWidth = 1.2
                bars.stroke()
            } else {
                bars.fill()
            }
            if mode == .continuing {
                NSBezierPath(ovalIn: NSRect(x: 14.4 - 1.9, y: 13.7 - 1.9, width: 3.8, height: 3.8)).fill()
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription =
            switch mode {
            case .tracking: String(localized: "wamadu, tracking")
            case .onBreak: String(localized: "wamadu, on break")
            case .continuing: String(localized: "wamadu, logging without asking")
            case .off: String(localized: "wamadu, off")
            }
        return image
    }

    #if DEBUG
        /// Writes every mode at 1x and 2x on light and dark menu bars.
        static func writePreviews(to directory: URL) throws {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let modes: [TrackerMode] = [.tracking, .onBreak, .continuing, .off]
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                for scale in [1, 2] {
                    let size = NSSize(width: 30 * modes.count, height: 30)
                    let rep = NSBitmapImageRep(
                        bitmapDataPlanes: nil, pixelsWide: Int(size.width) * scale,
                        pixelsHigh: Int(size.height) * scale,
                        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
                    rep.size = size
                    NSGraphicsContext.saveGraphicsState()
                    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
                    NSAppearance(named: appearance)!.performAsCurrentDrawingAppearance {
                        NSColor.windowBackgroundColor.setFill()
                        NSRect(origin: .zero, size: size).fill()
                        for (index, mode) in modes.enumerated() {
                            let rect = NSRect(x: 30 * index + 6, y: 6, width: 18, height: 18)
                            let glyph = NSImage(size: rect.size, flipped: false) { bounds in
                                image(for: mode).draw(in: bounds)
                                NSColor.labelColor.set()
                                bounds.fill(using: .sourceAtop)
                                return true
                            }
                            glyph.draw(in: rect)
                        }
                    }
                    NSGraphicsContext.restoreGraphicsState()
                    let url = directory.appending(path: "menubar-icon-\(name)@\(scale)x.png")
                    try rep.representation(using: .png, properties: [:])!.write(to: url)
                    print(url.path(percentEncoded: false))
                }
            }
        }
    #endif
}
