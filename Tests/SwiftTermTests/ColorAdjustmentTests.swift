import Testing
@testable import SwiftTerm

/// The colour adjustment a view applies to output written for a terminal
/// of the other polarity.
final class ColorAdjustmentTests {
    typealias RGB = ColorAdjustment.RGB
    func hex (_ v: Int) -> RGB { (Double ((v >> 16) & 255) / 255, Double ((v >> 8) & 255) / 255, Double (v & 255) / 255) }

    @Test func contrastMatchesWCAG () {
        #expect (abs (ColorAdjustment.contrast (hex (0x000000), hex (0xffffff)) - 21) < 0.01)
        #expect (abs (ColorAdjustment.contrast (hex (0x777777), hex (0xffffff)) - 4.48) < 0.02)
    }

    /// Light text drawn for a dark theme, on a light background: raised to
    /// 4.5:1, moved toward black, and no further than needed.
    @Test func lowContrastForegroundsAreRaisedJustEnough () {
        let white = hex (0xffffff), pale = hex (0xd8d8f0)
        let fixed = ColorAdjustment.ensuringContrast (pale, against: white, ratio: 4.5)
        let reached = ColorAdjustment.contrast (fixed, white)
        #expect (reached >= 4.5 && reached < 4.6)
        #expect (ColorAdjustment.relativeLuminance (fixed) < ColorAdjustment.relativeLuminance (pale))
        let fine = hex (0x202020)
        #expect (ColorAdjustment.ensuringContrast (fine, against: white, ratio: 4.5) == fine, "good contrast is left alone")
    }

    /// Catppuccin Mocha's panel over its base, mirrored onto a white theme:
    /// still a little off the background, now a little darker, still blue.
    @Test func mirroringKeepsAPanelsOffsetAndHue () {
        let base = hex (0x1e1e2e), panel = hex (0x313244)
        let mirror = ColorAdjustment.BackgroundMirror (source: ColorAdjustment.lightness (base), target: 1)
        let mirrored = ColorAdjustment.mirroringLightness (panel, mirror)
        let offset = ColorAdjustment.lightness (panel) - ColorAdjustment.lightness (base)
        #expect (abs ((1 - ColorAdjustment.lightness (mirrored)) - offset) < 0.01, "the same distance from the background, on its other side")
        #expect (mirrored.b > mirrored.r, "its blue tint stays")
        let back = ColorAdjustment.mirroringLightness (mirrored, .init (source: 1, target: ColorAdjustment.lightness (base)))
        #expect (abs (back.r - panel.r) < 0.01 && abs (back.b - panel.b) < 0.01, "mirroring back returns it")
        let plain = ColorAdjustment.mirroringLightness (hex (0x000000), .init (source: 0, target: 1))
        #expect (plain.r > 0.99 && plain.g > 0.99, "source 0, target 1 is the plain flip")
    }

    @Test func onlyTrueColorBackgroundsMirror () {
        let base = hex (0x1e1e2e)
        let adjustment = ColorAdjustment (minimumContrast: 4.5,
            backgroundMirror: .init (source: ColorAdjustment.lightness (base), target: 1))
        let palette = adjustment.adjust (foreground: hex (0xcdd6f4), background: base, backgroundIsTrueColor: false)
        #expect (palette.background == base, "a palette background is the viewer's own theme")
        let painted = adjustment.adjust (foreground: hex (0xcdd6f4), background: hex (0x45475a), backgroundIsTrueColor: true)
        #expect (ColorAdjustment.lightness (painted.background) > 0.8)
        #expect (ColorAdjustment.contrast (painted.foreground, painted.background) >= 4.5, "its text stays readable on the mirrored panel")
    }
}
