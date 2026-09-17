//
//  TerminalStateSerializer.swift
//
//  Turns a terminal back into the bytes that rebuild it.
//
//  This exists for clients that show a terminal they do not own — a pane
//  reattaching to a session held by a separate process, a second view of the
//  same session — where the screen has to be handed over rather than replayed
//  from the original byte stream. Replaying that stream is not equivalent: it
//  is unbounded, it costs a full re-parse, and a program that repaints with
//  cursor addressing (every full-screen TUI) produces a stream whose meaning
//  depends on the size it was written at.
//
//  What it restores: the scrollback and screen of the normal buffer with
//  their attributes, the alternate screen when it is active, cursor position
//  and visibility, the scroll region, and the modes a program sets and then
//  relies on — application cursor keys, application keypad, origin mode,
//  autowrap, reverse wrap, insert mode, bracketed paste, mouse tracking and
//  its encoding, focus reporting, kitty keyboard flags, and cursor style.
//
//  What it does not: the current pen (a program sets its own attributes
//  before drawing), OSC 8 hyperlinks, images, character-set designations, the
//  window title, and tab stops.
//
//  Created for Shiftover's pty host.

import Foundation

extension Terminal {

    /// The bytes that rebuild this terminal's contents and modes in a fresh
    /// terminal of the same size.
    ///
    /// Feeding them into a terminal of a *different* size still works — the
    /// text reflows — but a program that draws with cursor addressing will
    /// look wrong until it repaints, which is what the SIGWINCH from the
    /// resize provokes.
    /// - Parameters:
    ///   - maxScrollbackLines: how many lines above the screen to include.
    ///     `nil` keeps all of them. A client that saves this to disk wants a
    ///     bound; one handing a session over in memory usually does not.
    ///   - trimTrailingBlankLines: drops the empty rows below the last line
    ///     with content, and with them the final cursor placement. For a
    ///     handover the cursor has to land exactly where it was, so this is
    ///     off by default; for output shown above something new — a previous
    ///     session restored into a fresh terminal — those rows would push the
    ///     content off the screen.
    public func serializeState(maxScrollbackLines: Int? = nil,
                               trimTrailingBlankLines: Bool = false) -> [UInt8] {
        var out = Serializer(terminal: self, maxScrollbackLines: maxScrollbackLines,
                             trimTrailingBlankLines: trimTrailingBlankLines)
        out.run()
        return out.bytes
    }

    struct Serializer {
        let terminal: Terminal
        let maxScrollbackLines: Int?
        let trimTrailingBlankLines: Bool
        var bytes: [UInt8] = []
        var pen: Attribute?
        var lastLineWasFull = false

        init(terminal: Terminal, maxScrollbackLines: Int? = nil,
             trimTrailingBlankLines: Bool = false) {
            self.terminal = terminal
            self.maxScrollbackLines = maxScrollbackLines
            self.trimTrailingBlankLines = trimTrailingBlankLines
            bytes.reserveCapacity(4096)
        }

        mutating func run() {
            csi("0m")
            csi("H")
            csi("2J")
            csi("3J")

            let normal = terminal.normalBuffer
            var lineCount = min(normal.lines.count, normal.yBase + terminal.rows)
            if trimTrailingBlankLines {
                while lineCount > 0 {
                    let line = normal.lines[lineCount - 1]
                    if line.hasAnyContent() || hasPaintedCell(line) { break }
                    lineCount -= 1
                }
            }
            // Keep the screen whole and trim the oldest scrollback, which is
            // what a reader scrolling up would give up first anyway.
            var first = 0
            if let maxScrollbackLines {
                let allowed = maxScrollbackLines + terminal.rows
                if lineCount > allowed { first = lineCount - allowed }
            }
            for index in first..<lineCount {
                let line = normal.lines[index]
                // A soft-wrapped continuation is recreated by autowrap, so the
                // line before it is written whole and gets no newline.
                let nextWraps = index < lineCount - 1 && normal.lines[index + 1].isWrapped
                emit(line, keepFull: nextWraps)
                if index < lineCount - 1, !(nextWraps && lastLineWasFull) {
                    raw("\r\n")
                }
            }
            csi("0m")

            if terminal.isCurrentBufferAlternate {
                // `?1049h` saves the cursor, so the normal screen's cursor is
                // placed before the switch and comes back with `?1049l`.
                cursor(row: normal.y, col: normal.x)
                csi("?1049h")
                let alt = terminal.altBuffer
                for row in 0..<terminal.rows where alt.yBase + row < alt.lines.count {
                    let line = alt.lines[alt.yBase + row]
                    guard line.hasAnyContent() || hasPaintedCell(line) else { continue }
                    csi("\(row + 1);1H")
                    emit(line, keepFull: false)
                }
                csi("0m")
            }

            let active = terminal.buffer
            if active.scrollTop != 0 || active.scrollBottom != terminal.rows - 1 {
                csi("\(active.scrollTop + 1);\(active.scrollBottom + 1)r")
            }

            if terminal.applicationCursor { csi("?1h") }
            if terminal.applicationKeypad { raw("\u{1b}=") }
            if !terminal.wraparound { csi("?7l") }
            if terminal.reverseWraparound { csi("?45h") }
            if terminal.insertMode { csi("4h") }
            if terminal.bracketedPasteMode { csi("?2004h") }
            if terminal.sendFocus { csi("?1004h") }
            switch terminal.mouseMode {
            case .off: break
            case .x10: csi("?9h")
            case .vt200: csi("?1000h")
            case .buttonEventTracking: csi("?1002h")
            case .anyEvent: csi("?1003h")
            }
            if terminal.mouseMode != .off, let encoding = mouseEncodingMode {
                csi("?\(encoding)h")
            }
            let keyboardFlags = terminal.keyboardEnhancementFlags.rawValue
            if keyboardFlags != 0 { csi("=\(keyboardFlags);1u") }
            csi("\(cursorStyleParameter) q")

            if trimTrailingBlankLines {
                // No cursor placement: the rows it referred to are gone, and
                // whatever comes next continues after the last line.
                csi(terminal.cursorHidden ? "?25l" : "?25h")
                return
            }

            // Setting origin mode homes the cursor, so it precedes the final
            // placement, and the row is then relative to the scroll region.
            if terminal.originMode {
                csi("?6h")
                cursor(row: active.y - active.scrollTop, col: active.x)
            } else {
                cursor(row: active.y, col: active.x)
            }
            csi(terminal.cursorHidden ? "?25l" : "?25h")
        }

        var mouseEncodingMode: Int? {
            switch terminal.mouseProtocol {
            case .x10: return nil
            case .utf8: return 1005
            case .sgr: return 1006
            case .urxvt: return 1015
            case .sgrPixel: return 1016
            }
        }

        var cursorStyleParameter: Int {
            switch terminal.options.cursorStyle {
            case .blinkBlock: return 1
            case .steadyBlock: return 2
            case .blinkUnderline: return 3
            case .steadyUnderline: return 4
            case .blinkBar: return 5
            case .steadyBar: return 6
            }
        }

        func hasPaintedCell(_ line: BufferLine) -> Bool {
            for index in 0..<line.count where !Self.isDefault(line[index].attribute.bg) {
                return true
            }
            return false
        }

        static func isDefault(_ color: Attribute.Color) -> Bool {
            switch color {
            case .defaultColor, .defaultInvertedColor: return true
            default: return false
            }
        }

        mutating func raw(_ text: String) { bytes.append(contentsOf: text.utf8) }

        mutating func csi(_ text: String) {
            bytes.append(0x1b)
            bytes.append(0x5b)
            bytes.append(contentsOf: text.utf8)
            if text == "0m" { pen = nil }
        }

        mutating func cursor(row: Int, col: Int) {
            csi("\(row + 1);\(min(col, terminal.cols - 1) + 1)H")
        }

        mutating func emit(_ line: BufferLine, keepFull: Bool) {
            let count = min(line.count, terminal.cols)
            // A blank cell with a painted background is content: that is how
            // TUIs draw selection bars, progress fills and box shading. Only
            // cells that are empty *and* on the default background are
            // trimmed, and a line that wraps into the next is kept whole.
            var end = count
            while end > 0 && !keepFull {
                let cell = line[end - 1]
                if cell.code != 0 || !Self.isDefault(cell.attribute.bg)
                    || cell.attribute.style.contains(.inverse) { break }
                end -= 1
            }
            var column = 0
            while column < end {
                let cell = line[column]
                if cell.width == 0 {  // trailing half of a wide character
                    column += 1
                    continue
                }
                if pen != cell.attribute {
                    csi(Terminal.sgrParameters(for: cell.attribute) + "m")
                    pen = cell.attribute
                }
                if cell.code == 0 {
                    bytes.append(0x20)
                } else {
                    bytes.append(contentsOf: String(terminal.getCharacter(for: cell)).utf8)
                }
                column += max(1, Int(cell.width))
            }
            lastLineWasFull = end >= terminal.cols
            if pen != nil { csi("0m") }
        }
    }

    /// The SGR parameters that select `attribute` starting from a reset pen.
    ///
    /// Separate from the existing `Attribute.toSgr()`, which emits a trailing
    /// `;` for the basic colours and puts colour 16 in the basic range.
    static func sgrParameters(for attribute: Attribute) -> String {
        var parts = ["0"]
        let style = attribute.style
        if style.contains(.bold) { parts.append("1") }
        if style.contains(.dim) { parts.append("2") }
        if style.contains(.italic) { parts.append("3") }
        switch attribute.underlineStyle {
        case .none: if style.contains(.underline) { parts.append("4") }
        case .single: parts.append("4")
        case .double: parts.append("4:2")
        case .curly: parts.append("4:3")
        case .dotted: parts.append("4:4")
        case .dashed: parts.append("4:5")
        }
        if style.contains(.blink) { parts.append("5") }
        if style.contains(.inverse) { parts.append("7") }
        if style.contains(.invisible) { parts.append("8") }
        if style.contains(.crossedOut) { parts.append("9") }
        appendColor(attribute.fg, base: 30, bright: 90, extended: 38, into: &parts)
        appendColor(attribute.bg, base: 40, bright: 100, extended: 48, into: &parts)
        if let underline = attribute.underlineColor {
            appendColor(underline, base: nil, bright: nil, extended: 58, into: &parts)
        }
        return parts.joined(separator: ";")
    }

    private static func appendColor(_ color: Attribute.Color, base: Int?, bright: Int?,
                                    extended: Int, into parts: inout [String]) {
        switch color {
        case .defaultColor, .defaultInvertedColor:
            break
        case .ansi256(let code):
            if code < 8, let base {
                parts.append("\(base + Int(code))")
            } else if code < 16, let bright {
                parts.append("\(bright + Int(code) - 8)")
            } else {
                parts.append("\(extended);5;\(code)")
            }
        case .trueColor(let r, let g, let b):
            parts.append("\(extended);2;\(r);\(g);\(b)")
        }
    }
}
