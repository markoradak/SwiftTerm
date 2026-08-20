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
