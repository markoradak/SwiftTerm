//
//  ColorAdjustment.swift
//
//  How a view adjusts colours it did not choose: output written for another
//  machine's terminal, whose background may be of the other polarity (a dark
//  theme there, a light one here). Programs paint 24-bit colours chosen for
//  the background they detected, which a palette swap cannot reach.
//

import Foundation

public struct ColorAdjustment: Equatable, Sendable {
    /// Each foreground moves toward white or black until it has at least this
    /// WCAG contrast against its cell's background. 1 leaves foregrounds alone.
    public var minimumContrast: Double
    /// When set, mirrors the lightness of 24-bit backgrounds across the two
    /// themes' backgrounds, keeping hue and chroma (OKLCH): a panel a little
    /// lighter than the other terminal's dark background becomes a little
    /// darker than this one's light background, and the reverse.
    public var backgroundMirror: BackgroundMirror?

    /// The OKLab lightness of the background each terminal's theme draws.
    /// `source 0, target 1` is the plain flip, L → 1 − L.
    public struct BackgroundMirror: Equatable, Sendable {
        public var source: Double
        public var target: Double
        public init (source: Double, target: Double) { self.source = source; self.target = target }
    }

    public init (minimumContrast: Double = 1, backgroundMirror: BackgroundMirror? = nil) {
        self.minimumContrast = minimumContrast
        self.backgroundMirror = backgroundMirror
    }

    public typealias RGB = (r: Double, g: Double, b: Double)

    /// Adjusts one cell's colours. `background` is flipped only when it is a
    /// 24-bit colour; the foreground is then fitted to the result.
    public func adjust (foreground: RGB, background: RGB, backgroundIsTrueColor: Bool) -> (foreground: RGB, background: RGB) {
        var bg = background
        if let mirror = backgroundMirror, backgroundIsTrueColor { bg = Self.mirroringLightness (background, mirror) }
        let fg = minimumContrast > 1 ? Self.ensuringContrast (foreground, against: bg, ratio: minimumContrast) : foreground
        return (fg, bg)
    }

    // MARK: - WCAG contrast

    static func linear (_ c: Double) -> Double {
        c <= 0.04045 ? c / 12.92 : pow ((c + 0.055) / 1.055, 2.4)
    }

    static func gamma (_ c: Double) -> Double {
        let v = c <= 0.0031308 ? c * 12.92 : 1.055 * pow (c, 1 / 2.4) - 0.055
        return min (1, max (0, v))
    }

    public static func relativeLuminance (_ c: RGB) -> Double {
        0.2126 * linear (c.r) + 0.7152 * linear (c.g) + 0.0722 * linear (c.b)
    }

    public static func contrast (_ a: RGB, _ b: RGB) -> Double {
        let la = relativeLuminance (a), lb = relativeLuminance (b)
        return (max (la, lb) + 0.05) / (min (la, lb) + 0.05)
    }

    static func mix (_ a: RGB, _ b: RGB, _ t: Double) -> RGB {
        (a.r + (b.r - a.r) * t, a.g + (b.g - a.g) * t, a.b + (b.b - a.b) * t)
    }

    /// The least change to `foreground` that reaches `ratio`: moved toward
    /// white on a dark background, black on a light one (the other way when
    /// that cannot get there), and the better of the two when neither can.
    public static func ensuringContrast (_ foreground: RGB, against background: RGB, ratio: Double) -> RGB {
        guard contrast (foreground, background) < ratio else { return foreground }
        let white: RGB = (1, 1, 1), black: RGB = (0, 0, 0)
        let first = relativeLuminance (background) < 0.5 ? white : black
        for target in [first, first == white ? black : white] where contrast (target, background) >= ratio {
            var low = 0.0, high = 1.0
            for _ in 0..<16 {
                let mid = (low + high) / 2
                if contrast (mix (foreground, target, mid), background) >= ratio { high = mid } else { low = mid }
            }
            return mix (foreground, target, high)
        }
        return contrast (white, background) >= contrast (black, background) ? white : black
    }

    // MARK: - OKLab lightness

    static func oklab (_ c: RGB) -> (l: Double, a: Double, b: Double) {
        let r = linear (c.r), g = linear (c.g), b = linear (c.b)
        let l = cbrt (0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt (0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt (0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)
        return (0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s,
                1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s,
                0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s)
    }

    /// OKLab lightness, 0 (black) to 1 (white).
    public static func lightness (_ c: RGB) -> Double { oklab (c).l }

    public static func mirroringLightness (_ c: RGB, _ mirror: BackgroundMirror) -> RGB {
        let lab = oklab (c)
        let flipped = min (1, max (0, mirror.target - (lab.l - mirror.source)))
        let a = lab.a, bb = lab.b
        let l2 = pow (flipped + 0.3963377774 * a + 0.2158037573 * bb, 3)
        let m2 = pow (flipped - 0.1055613458 * a - 0.0638541728 * bb, 3)
        let s2 = pow (flipped - 0.0894841775 * a - 1.2914855480 * bb, 3)
        return (gamma (4.0767416621 * l2 - 3.3077115913 * m2 + 0.2309699292 * s2),
                gamma (-1.2684380046 * l2 + 2.6097574011 * m2 - 0.3413193965 * s2),
                gamma (-0.0041960863 * l2 - 0.7034186147 * m2 + 1.7076147010 * s2))
    }
}
