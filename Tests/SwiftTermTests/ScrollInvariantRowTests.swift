import Testing
@testable import SwiftTerm

/// A position on the active screen, kept as a scroll-invariant row, still
/// names the same line after output scrolls the screen and while the view is
/// scrolled back.
final class ScrollInvariantRowTests {
    final class Quiet: TerminalDelegate {
        func send(source: Terminal, data: ArraySlice<UInt8>) {}
    }

    @Test func rowSurvivesScrollingAndScrollback() {
        let quiet = Quiet()
        let terminal = Terminal(delegate: quiet, options: TerminalOptions(cols: 20, rows: 5, scrollback: 100))
        terminal.feed(text: "one\r\ntwo\r\n$ ")
        let anchor = terminal.scrollInvariantRow(screenRow: terminal.buffer.y)
        terminal.feed(text: "a long command that wraps")
        terminal.feed(text: "\r\n1\r\n2\r\n3\r\n4\r\n5")
        terminal.buffer.yDisp -= 2 // The view scrolled back, as a host reading history.
        let line = terminal.getScrollInvariantLine(row: anchor)
        #expect(line?.translateToString(trimRight: true) == "$ a long command tha")
        let next = terminal.getScrollInvariantLine(row: anchor + 1)
        #expect(next?.isWrapped == true)
        #expect(next?.translateToString(trimRight: true) == "t wraps")
        #expect(terminal.getScrollInvariantLine(row: anchor + 2)?.isWrapped == false)
    }
}
