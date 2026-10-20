#if os(macOS)
import AppKit
import Testing
@testable import SwiftTerm

/// A view on a fixed grid mirrors a terminal sized elsewhere: its frame and
/// font change without resizing (and so reflowing) the grid.
@MainActor
final class FixedGridSizeTests {
    @Test func gridHoldsThroughFrameAndFontChanges() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular))
        view.fixedGridSize = (cols: 100, rows: 30)
        #expect(view.getTerminal().cols == 100 && view.getTerminal().rows == 30)
        view.feed(text: String(repeating: "x", count: 150))
        view.setFrameSize(NSSize(width: 300, height: 200))
        view.font = NSFont.monospacedSystemFont(ofSize: 8, weight: .regular)
        #expect(view.getTerminal().cols == 100 && view.getTerminal().rows == 30)
        #expect(view.getTerminal().getLine(row: 0)?.translateToString(trimRight: true).count == 100, "nothing reflowed")
        let fitted = view.getOptimalFrameSize()
        view.setFrameSize(fitted.size)
        #expect(view.getTerminal().cols == 100)

        view.fixedGridSize = nil
        view.setFrameSize(NSSize(width: 300, height: 200))
        #expect(view.getTerminal().cols != 100, "back on the view's own fit")
    }

    /// The drawn background of a 24-bit cell follows the adjustment, and
    /// goes back when it is cleared (the attribute cache is dropped).
    @Test func colorAdjustmentReachesDrawnAttributes() {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 600, height: 400), font: nil)
        let attribute = Attribute(fg: .trueColor(red: 205, green: 214, blue: 244), bg: .trueColor(red: 0x45, green: 0x47, blue: 0x5a),
                                  style: .none)
        func background() -> ColorAdjustment.RGB? { (view.getAttributes(attribute, withUrl: false)?[.backgroundColor] as? NSColor)?.adjustmentRGB }
        let original = background()
        view.colorAdjustment = ColorAdjustment(minimumContrast: 4.5, backgroundMirror: .init(source: 0.25, target: 1))
        let mirrored = background()
        #expect(mirrored.map { ColorAdjustment.lightness($0) } ?? 0 > 0.8)
        view.colorAdjustment = nil
        #expect(background().map { abs($0.r - (original?.r ?? -1)) < 0.001 } == true)
    }
}
#endif
