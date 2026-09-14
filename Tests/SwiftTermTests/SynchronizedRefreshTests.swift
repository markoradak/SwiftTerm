//
//  SynchronizedRefreshTests.swift
//
//  Ending a synchronized frame (DECSET 2026) used to mark the whole screen
//  dirty, so an agent TUI that repaints three rows redrew all of them, every
//  frame. These tests pin the narrow refresh and — more importantly — the case
//  that made the blanket refresh look necessary: a display tick that consumes
//  the accumulated update range while the frame is still open.
//
import Foundation
import Testing

@testable import SwiftTerm

final class SynchronizedRefreshTests: TerminalDelegate {
    func send(source: Terminal, data: ArraySlice<UInt8>) {}

    private func makeTerminal () -> Terminal {
        let terminal = Terminal(delegate: self, options: TerminalOptions(cols: 80, rows: 25))
        terminal.feed(text: "\u{1b}[2J")
        terminal.clearUpdateRange()
        return terminal
    }

    @Test func testSynchronizedFrameRefreshesOnlyTheRowsItChanged () {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?2026h\u{1b}[6;1Hchanged\u{1b}[?2026l")
        let range = terminal.getUpdateRange()
        #expect(range != nil)
        // Row 6 in one-based cursor terms is index 5. The range may still start
        // at the row the cursor was parked on when the frame opened — that comes
        // from the ordinary write path, not from ending the frame. What matters
        // is that ending it no longer stretches the range to the whole screen.
        #expect(range?.endY == 5)
        #expect((range?.endY ?? 0) < terminal.rows - 1,
                "ending a synchronized frame must not dirty the whole screen")
    }

    @Test func testUnchangedSynchronizedFrameDoesNotRepaintEverything () {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[3;1Hstable line")
        terminal.clearUpdateRange()
        // Rewrite the same row with byte-identical content inside a frame.
        terminal.feed(text: "\u{1b}[?2026h\u{1b}[3;1Hstable line\u{1b}[?2026l")
        let range = terminal.getUpdateRange()
        if let range {
            #expect(range.startY >= 2 && range.endY <= 2,
                    "an identical repaint must not dirty rows it did not change")
        }
    }

    @Test func testFrameRecoversRowsAfterADisplayTickConsumedTheRange () {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?2026h\u{1b}[10;1Hwritten while open")
        // This is what a display tick does: it reads the range and clears it.
        _ = terminal.getUpdateRange()
        terminal.clearUpdateRange()
        terminal.feed(text: "\u{1b}[?2026l")
        let range = terminal.getUpdateRange()
        #expect(range != nil, "closing the frame must rediscover the row that changed")
        #expect(range?.startY == 9)
        #expect(range?.endY == 9)
    }

    @Test func testSwitchingScreensInsideAFrameFallsBackToAFullRefresh () {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[?2026h\u{1b}[?1049h")
        terminal.clearUpdateRange()
        terminal.feed(text: "\u{1b}[?2026l")
        let range = terminal.getUpdateRange()
        #expect(range != nil)
        #expect(range?.startY == 0)
        #expect(range?.endY == terminal.rows - 1)
    }

    @Test func testLineVersionOnlyMovesWhenRenderedContentChanges () {
        let terminal = makeTerminal()
        terminal.feed(text: "\u{1b}[1;1Hhello")
        let line = terminal.buffer.lines [terminal.buffer.yBase]
        let afterWrite = line.version
        terminal.feed(text: "\u{1b}[1;1Hhello")
        #expect(line.version == afterWrite, "rewriting identical content must not bump the version")
        terminal.feed(text: "\u{1b}[1;1Hhellp")
        #expect(line.version != afterWrite, "a real change must bump the version")
    }
}
