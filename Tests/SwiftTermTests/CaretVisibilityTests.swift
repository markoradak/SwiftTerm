//
//  CaretVisibilityTests.swift
//
//  Pins the caret's visibility mechanism: hiding the cursor must HIDE the
//  caret view, not remove it from the view hierarchy.
//
//  Removing it is not merely a different way to achieve the same pixels. A
//  structural view-hierarchy mutation tears the caret's autoresizing
//  constraints out of the window's shared NSISEngine, which notifies the
//  constraint-based hosting view — and in an AppKit host embedding SwiftUI (or
//  vice-versa) that invalidates the hosted view's layout metrics and re-runs
//  layout for the entire window. Full-screen TUIs toggle the cursor around
//  every repaint, so at frame rate, per terminal, that is a large and entirely
//  avoidable cost.
//

#if os(macOS)
import XCTest
import AppKit
@testable import SwiftTerm

final class CaretVisibilityTests: XCTestCase {

    private func makeView() -> TerminalView {
        let view = TerminalView(frame: CGRect(x: 0, y: 0, width: 400, height: 300))
        // Give it a window so layout/geometry behave as they do in an app.
        let window = NSWindow(
            contentRect: view.frame, styleMask: [.titled],
            backing: .buffered, defer: false)
        window.contentView?.addSubview(view)
        return view
    }

    /// The caret must stay in the hierarchy across a hide/show cycle.
    func testCursorToggleDoesNotMutateTheViewHierarchy() {
        let view = makeView()
        let terminal = view.getTerminal()

        // Mount the caret via the normal path.
        terminal.showCursor()
        view.updateDisplay(notifyAccessibility: false)
        XCTAssertNotNil(view.caretView?.superview,
                        "caret should be mounted once the cursor is shown")
        let mountedIn = view.caretView?.superview

        terminal.hideCursor()
        view.updateDisplay(notifyAccessibility: false)
        XCTAssertEqual(view.caretView?.superview, mountedIn,
                       "hiding the cursor must NOT remove the caret view")
        XCTAssertEqual(view.caretView?.isHidden, true,
                       "hiding the cursor must hide the caret view")

        terminal.showCursor()
        view.updateDisplay(notifyAccessibility: false)
        XCTAssertEqual(view.caretView?.superview, mountedIn,
                       "showing the cursor must not re-parent the caret view")
        XCTAssertEqual(view.caretView?.isHidden, false,
                       "showing the cursor must reveal the caret view")
    }

    // MARK: caret glyph memo

    /// The caret rebuilds an `NSAttributedString` + a `CTLine` on every display
    /// tick, and `updateCursorPosition` runs one per tick — so for a busy pane
    /// that was frame-rate glyph construction for a cell that usually has not
    /// changed. Memoizing is only safe if a real change still invalidates, so
    /// both directions are pinned here by comparing the CTLine *object*: a memo
    /// hit reuses it, a miss builds a new one. Asserting merely that it is
    /// non-nil would pass even with the memo permanently stuck.

    func testUnchangedCellReusesTheCaretGlyph() {
        let view = makeView()
        view.feed(text: "\u{1b}[?25h")
        view.updateDisplay(notifyAccessibility: false)
        let first = try? XCTUnwrap(view.caretView?.ctline)
        XCTAssertNotNil(first)

        // Nothing about the cell or the colours changed.
        view.updateDisplay(notifyAccessibility: false)
        XCTAssertTrue(view.caretView?.ctline === first,
                      "an unchanged cell must reuse the memoized CTLine")
    }

    /// `nativeForegroundColor` is folded into the glyph's attributes as the
    /// background whenever `caretTextColor` is nil, but changing it does NOT
    /// route through `updateView()` — so this is the case the memo *key* has to
    /// cover on its own. (The `caretColor` test below is belt-and-braces: it
    /// passes via `updateView()` even if the key omitted the colour.)
    func testNativeForegroundChangeInvalidatesTheCaretGlyph() {
        let view = makeView()
        view.caretTextColor = nil
        view.feed(text: "\u{1b}[?25h")
        view.updateDisplay(notifyAccessibility: false)
        let first = view.caretView?.ctline
        XCTAssertNotNil(first)

        view.nativeForegroundColor = .systemTeal
        view.updateDisplay(notifyAccessibility: false)
        XCTAssertFalse(view.caretView?.ctline === first,
                       "a native-foreground change must rebuild the caret glyph")
    }

    func testColourChangeInvalidatesTheCaretGlyph() {
        let view = makeView()
        view.feed(text: "\u{1b}[?25h")
        view.updateDisplay(notifyAccessibility: false)
        let first = view.caretView?.ctline
        XCTAssertNotNil(first)

        view.caretColor = .systemRed
        view.updateDisplay(notifyAccessibility: false)
        XCTAssertFalse(view.caretView?.ctline === first,
                       "a colour change must rebuild the caret glyph")
    }

    /// The same, driven the way a program actually does it — the DECTCEM
    /// escape sequences fed through the emulator.
    func testDECTCEMSequencesDriveIsHiddenOnly() {
        let view = makeView()

        view.feed(text: "\u{1b}[?25h")
        view.updateDisplay(notifyAccessibility: false)
        let mountedIn = view.caretView?.superview
        XCTAssertNotNil(mountedIn)
        XCTAssertEqual(view.caretView?.isHidden, false)

        // A TUI repaint cycle: hide, draw, show — many times a second.
        for _ in 0..<50 {
            view.feed(text: "\u{1b}[?25l")
            view.updateDisplay(notifyAccessibility: false)
            XCTAssertEqual(view.caretView?.superview, mountedIn,
                           "caret must never leave the hierarchy")
            view.feed(text: "\u{1b}[?25h")
            view.updateDisplay(notifyAccessibility: false)
            XCTAssertEqual(view.caretView?.superview, mountedIn,
                           "caret must never leave the hierarchy")
        }
        XCTAssertEqual(view.caretView?.isHidden, false,
                       "the final state was cursor-visible")
    }
}
#endif
