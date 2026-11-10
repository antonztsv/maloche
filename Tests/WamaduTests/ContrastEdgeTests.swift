import AppKit
import SwiftUI
import Testing

@testable import Wamadu

/// With increased contrast own shapes get a 1 pt edge inside, the normal look stays without one.
@MainActor @Suite(.serialized) struct ContrastEdgeTests {
    /// Alpha of the top edge's middle pixel and of the center, drawn at 1 pixel per point.
    private static func alphas(of view: some View) throws -> (edge: CGFloat, center: CGFloat) {
        let renderer = ImageRenderer(content: view.frame(width: 40, height: 20))
        renderer.scale = 1
        let image = NSBitmapImageRep(cgImage: try #require(renderer.cgImage))
        func alpha(_ x: Int, _ y: Int) -> CGFloat { image.colorAt(x: x, y: y)?.alphaComponent ?? 0 }
        return (alpha(20, 0), alpha(20, 10))
    }

    @Test func canvasShapesGetAnEdgeOnlyWithIncreasedContrast() throws {
        for contrast in [ColorSchemeContrast.standard, .increased] {
            let alphas = try Self.alphas(
                of: Canvas { context, size in
                    context.contrastEdge(
                        Path(roundedRect: CGRect(origin: .zero, size: size), cornerRadius: 4), contrast: contrast)
                })
            #expect((alphas.edge > 0) == (contrast == .increased), "\(contrast): \(alphas)")
            #expect(alphas.center == 0)
        }
    }

    @Test func viewsGetAnEdgeOnlyWithIncreasedContrast() throws {
        for contrast in [ColorSchemeContrast.standard, .increased] {
            let alphas = try Self.alphas(of: Color.clear.contrastEdge(cornerRadius: 6, contrast: contrast))
            #expect((alphas.edge > 0) == (contrast == .increased), "\(contrast): \(alphas)")
            #expect(alphas.center == 0)
        }
    }
}
