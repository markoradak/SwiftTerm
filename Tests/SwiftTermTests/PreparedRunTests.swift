//
//  PreparedRunTests.swift
//
//  The draw loop reads each CoreText run's attributes straight out of the
//  CFDictionary instead of bridging it into a Swift dictionary. That lookup
//  depends on CFEqual matching a separately allocated key string; if it ever
//  stopped matching, every run would silently render with default colours and
//  no decorations rather than failing, so it is pinned here.
//
#if os(macOS)
import XCTest
import CoreText
@testable import SwiftTerm

final class PreparedRunTests: XCTestCase {
    private func runs (_ string: NSAttributedString) -> [CTRun] {
        let line = CTLineCreateWithAttributedString(string)
        return (CTLineGetGlyphRuns(line) as? [CTRun]) ?? []
    }

    private func prepared (_ attributes: [NSAttributedString.Key: Any]) -> TerminalView.PreparedRun? {
        let string = NSAttributedString(string: "abc", attributes: attributes)
        guard let run = runs(string).first else { return nil }
        return TerminalView.PreparedRun(run: run,
                                        glyphCount: CTRunGetGlyphCount(run),
                                        attributes: CTRunGetAttributes(run))
    }

    func testReadsColoursAndFontWithoutBridging () {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let info = prepared([.font: font,
                             .foregroundColor: NSColor.red,
                             .backgroundColor: NSColor.blue])
        XCTAssertNotNil(info)
        XCTAssertEqual(info?.font, font)
        XCTAssertEqual(info?.foregroundColor, NSColor.red)
        XCTAssertEqual(info?.backgroundColor, NSColor.blue)
        XCTAssertNil(info?.selectionBackgroundColor)
        XCTAssertEqual(info?.glyphCount, 3)
    }

    func testSelectionBackgroundUsesTheCustomKey () {
        let info = prepared([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular),
                             .selectionBackgroundColor: NSColor.green])
        XCTAssertEqual(info?.selectionBackgroundColor, NSColor.green)
    }

    func testAbsentAttributesReadAsNilRatherThanThrowing () {
        let info = prepared([.font: NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)])
        XCTAssertNotNil(info)
        XCTAssertNil(info?.foregroundColor)
        XCTAssertNil(info?.backgroundColor)
        XCTAssertFalse(info?.hasDecorations ?? true)
    }

    func testDecorationsAreDetectedForUnderlineAndStrikethrough () {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        XCTAssertTrue(prepared([.font: font, .underlineStyle: NSUnderlineStyle.single.rawValue])?.hasDecorations ?? false)
        XCTAssertTrue(prepared([.font: font, .strikethroughStyle: NSUnderlineStyle.single.rawValue])?.hasDecorations ?? false)
    }

    func testBridgedAttributesStillCarryEverythingForDecoratedRuns () {
        let font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        let info = prepared([.font: font,
                             .underlineStyle: NSUnderlineStyle.single.rawValue,
                             .underlineColor: NSColor.orange])
        let bridged = info?.bridgedAttributes ?? [:]
        XCTAssertEqual(bridged[.underlineColor] as? NSColor, NSColor.orange)
        XCTAssertNotNil(bridged[.underlineStyle])
    }
}
#endif
