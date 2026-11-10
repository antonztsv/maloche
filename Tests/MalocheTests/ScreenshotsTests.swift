import AppKit
import MalocheCore
import SwiftUI
import Testing

@testable import Maloche

/// The screenshot mode draws without ever taking the keyboard from the app in front.
@MainActor @Suite struct ScreenshotsTests {
    @Test func renderingDrawsTheViewWithoutAKeyOrVisibleWindow() throws {
        var becameKey = 0
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: nil, queue: nil
        ) { _ in becameKey += 1 }
        defer { NotificationCenter.default.removeObserver(observer) }

        let view = AnyView(Text(verbatim: "maloche").font(.title).padding(20))
        let image = try Screenshots.image(of: view, appearance: NSAppearance(named: .aqua)!)

        #expect(becameKey == 0)
        #expect(NSApplication.shared.keyWindow == nil)
        #expect(NSApplication.shared.windows.allSatisfy { !$0.isVisible })
        #expect(image.pixelsWide > 40)
        let drawn = (0..<image.pixelsWide).contains { x in
            (0..<image.pixelsHigh).contains { y in
                guard let color = image.colorAt(x: x, y: y) else { return false }
                return color.alphaComponent > 0.5 && color.brightnessComponent < 0.5
            }
        }
        #expect(drawn, "the text is drawn dark on the light background")
    }

    @Test func theScreenshotWindowCannotTakeTheKeyboard() {
        #expect(!Screenshots.Window().canBecomeKey)
        #expect(!Screenshots.Window().canBecomeMain)
    }
}
