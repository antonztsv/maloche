import AppKit
import MalocheCore
import Testing

@testable import Maloche

/// Text reads at 4.5:1, and every other color is a semantic system color the system keeps readable.
@MainActor @Suite struct ContrastTests {
    /// Increased contrast resolves system colors like the standard appearances here, it is checked by hand.
    private static let appearances: [NSAppearance.Name] = [.aqua, .darkAqua]

    private static func rgba(_ color: NSColor, in name: NSAppearance.Name) -> [Double] {
        var components = [0.0, 0.0, 0.0, 1.0]
        NSAppearance(named: name)!.performAsCurrentDrawingAppearance {
            let srgb = color.usingColorSpace(.sRGB)!
            components = [srgb.redComponent, srgb.greenComponent, srgb.blueComponent, srgb.alphaComponent]
        }
        return components
    }

    /// WCAG contrast of the color drawn over the background, translucent colors blended first.
    static func contrast(_ color: NSColor, _ background: NSColor, in name: NSAppearance.Name) -> Double {
        let front = rgba(color, in: name)
        let back = rgba(background, in: name)
        let blended = (0..<3).map { front[$0] * front[3] + back[$0] * (1 - front[3]) }
        func luminance(_ c: [Double]) -> Double {
            func linear(_ v: Double) -> Double { v <= 0.04045 ? v / 12.92 : pow((v + 0.055) / 1.055, 2.4) }
            return 0.2126 * linear(c[0]) + 0.7152 * linear(c[1]) + 0.0722 * linear(c[2])
        }
        let (a, b) = (luminance(blended), luminance(Array(back.prefix(3))))
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    // the glass panel has no fixed color, the window background stands in for it
    @Test func labelTextReadsInLightAndDark() {
        for name in Self.appearances {
            let ratio = Self.contrast(.labelColor, .windowBackgroundColor, in: name)
            #expect(ratio >= 4.5, "\(name.rawValue): \(String(format: "%.2f", ratio)):1")
        }
    }

    @Test func labelTextReadsOnTheNowRowTint() {
        for name in Self.appearances {
            let back = Self.rgba(.windowBackgroundColor, in: name)
            let tint = Self.rgba(DashboardView.nowTint, in: name)
            let mix = (0..<3).map { tint[$0] * tint[3] + back[$0] * (1 - tint[3]) }
            let row = NSColor(srgbRed: mix[0], green: mix[1], blue: mix[2], alpha: 1)
            let ratio = Self.contrast(.labelColor, row, in: name)
            #expect(ratio >= 4.5, "\(name.rawValue): \(String(format: "%.2f", ratio)):1")
        }
    }

    /// Fixed color values in the sources, besides the black that tints the menu bar template image.
    @Test func theAppDefinesNoColorsOfItsOwn() throws {
        let sources = URL(filePath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appending(path: "Sources")
        let pattern = try Regex(
            #"(Color|NSColor)\((red|white|hue|calibrated|device|srgb|displayP3|genericGamma|\.sRGB|\.displayP3)"#
                + #"|#colorLiteral|NSColor\.(black|white|gray|darkGray|lightGray|red|green|blue|orange|yellow|purple|brown)(?!\w)"#
                + #"|Color\.(black|white|gray)(?!\w)"#)
        let allowed = ["MenuBarIcon.swift: NSColor.black"]
        var found: [String] = []
        var scanned = 0
        let files = try #require(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let file as URL in files where file.pathExtension == "swift" {
            scanned += 1
            for line in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                for match in line.matches(of: pattern) {
                    let hit = "\(file.lastPathComponent): \(line[match.range])"
                    if !allowed.contains(hit) { found.append(hit) }
                }
            }
        }
        #expect(scanned > 20, "the sources were found")
        #expect(found.isEmpty, "\(found)")
    }
}
