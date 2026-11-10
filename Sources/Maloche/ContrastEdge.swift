import AppKit
import SwiftUI

extension GraphicsContext {
    /// A 1 pt separator edge inside the shape with increased contrast, as the system outlines its controls then.
    func contrastEdge(_ path: Path, contrast: ColorSchemeContrast) {
        guard contrast == .increased else { return }
        var context = self
        context.clip(to: path)
        // twice the width, the clip keeps the inner half
        context.stroke(path, with: .color(Color(nsColor: .separatorColor)), lineWidth: 2)
    }
}

extension View {
    /// A 1 pt separator edge with increased contrast, as the system outlines its controls then.
    func contrastEdge(cornerRadius: CGFloat, contrast: ColorSchemeContrast) -> some View {
        overlay {
            if contrast == .increased {
                RoundedRectangle(cornerRadius: cornerRadius).strokeBorder(Color(nsColor: .separatorColor))
            }
        }
    }
}
