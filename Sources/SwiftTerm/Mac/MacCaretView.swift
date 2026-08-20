//
//  MacCaretView.swift
//  
// Implements the caret in the Mac caret view
// TODO: looks like I can kill sub now. unless it can be used to draw a border when out of focus
//
//  Created by Miguel de Icaza on 3/20/20.
//

#if os(macOS)
import Foundation
import AppKit
import CoreText
import CoreGraphics
import CoreText

// The CaretView is used to show the cursor
class CaretView: NSView, CALayerDelegate {
    weak var terminal: TerminalView?
    var ctline: CTLine?
    var bgColor: CGColor
    var tracksFocus = true
    
    public init (frame: CGRect, cursorStyle: CursorStyle, terminal: TerminalView)
    {
        self.terminal = terminal
        style = cursorStyle
        bgColor = caretColor.cgColor
        super.init(frame: frame)
        wantsLayer = true

        updateView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // Enable transparency support for the cursor (matches iOS behavior)
    override func makeBackingLayer() -> CALayer {
        let layer = super.makeBackingLayer()
        layer.isOpaque = false
        layer.backgroundColor = NSColor.clear.cgColor
        return layer
    }
    
    /// The (character, attribute, colors) the current `ctline` was built from,
    /// so an unchanged cell can skip the rebuild entirely.
    private var renderedKey: CaretTextKey?

    /// Identity of a rendered caret glyph. Compared instead of rebuilding.
    private struct CaretTextKey: Equatable {
        let code: Int32
        let attribute: Attribute
        let caret: NSColor
        let caretText: NSColor?
        /// Used as the background when `caretTextColor` is nil, so a theme
        /// change that only moves the foreground still invalidates.
        let nativeForeground: NSColor?
    }

    func setText (ch: CharData) {
        // `updateCursorPosition()` calls this on EVERY display tick, and a
        // display tick happens whenever the pty produced output — so for a busy
        // agent pane this ran at frame rate. Building an `NSAttributedString`
        // and a `CTLine` for a cell that has not changed is pure waste, and
        // `setNeedsDisplay` on top of it keeps the window's display cycle alive
        // for a caret that looks identical.
        //
        // The cursor sits on the same character for most of a repaint burst
        // (and on a space at an idle prompt), so the hit rate is high.
        let key = CaretTextKey(
            code: ch.code,
            attribute: ch.attribute,
            caret: caretColor,
            caretText: caretTextColor,
            nativeForeground: terminal?.nativeForegroundColor)
        if key == renderedKey, ctline != nil { return }
        renderedKey = key

        let character = terminal?.terminal.getCharacter(for: ch) ?? " "
        let res = NSAttributedString (
            string: String (character),
            attributes: terminal?.getAttributedValue(ch.attribute, usingFg: caretColor, andBg: caretTextColor ?? terminal?.nativeForegroundColor ?? NSColor.black))
        ctline = CTLineCreateWithAttributedString(res)

        setNeedsDisplay(bounds)
    }
    
    var style: CursorStyle {
        didSet {
            updateCursorStyle ()
        }
    }
    
    func updateCursorStyle () {
        switch style {
        case .blinkUnderline, .blinkBlock, .blinkBar:
            updateAnimation(to: true)
        case .steadyBar, .steadyBlock, .steadyUnderline:
            updateAnimation(to: false)
        }
        updateView ()
    }
    
    func updateAnimation (to: Bool) {
        layer?.removeAllAnimations()
        self.layer?.opacity = 1
        if to {
            let anim = CABasicAnimation.init(keyPath: #keyPath (CALayer.opacity))
            anim.duration = 0.7
            anim.autoreverses = true
            anim.repeatCount = Float.infinity
            anim.fromValue = NSNumber (floatLiteral: 1)
            anim.toValue = NSNumber (floatLiteral: 0)
            anim.timingFunction = CAMediaTimingFunction (name: .easeIn)
            layer?.add(anim, forKey: #keyPath (CALayer.opacity))
        }
    }
    
    func disableAnimations () {
        layer?.removeAllAnimations()
        layer?.opacity = 1
    }
    
    public var defaultCaretColor = NSColor.selectedControlColor
    
    public var caretColor: NSColor = NSColor.selectedControlColor {
        didSet {
            bgColor = caretColor.cgColor
            updateView()
        }
    }

    public var defaultCaretTextColor: NSColor? = nil
    public var caretTextColor: NSColor? = nil {
        didSet {
            updateView()
        }
    }

    public var focused: Bool = false {
        didSet {
            updateView()
        }
    }

    func updateView() {
        // Appearance changed (colors, font, cursor style) — drop the memoized
        // glyph so the next `setText` rebuilds rather than reusing a `CTLine`
        // built with the old attributes. Cheap belt-and-braces on top of the
        // key comparison, which cannot see everything `getAttributedValue`
        // folds in (notably the font).
        renderedKey = nil
        setNeedsDisplay(bounds)
    }
    
    func draw(_ layer: CALayer, in context: CGContext) {
        drawCursor (in: context, hasFocus: tracksFocus ? (terminal?.hasFocus ?? true) : true)
    }
    
    override func draw(_ dirtyRect: NSRect) {
    }
    
    override func hitTest(_ point: NSPoint) -> NSView? {
        // we do not want to steal hits, let the terminal view take them
        return nil
    }
}
#endif
