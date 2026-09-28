//
//  ThemeQueryTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

struct ThemeQueryTests {
    @Test("No theme parameter pins no axis")
    func emptyIsNoPin() throws {
        #expect(try ThemeQuery.parse(nil) == [:])
        #expect(try ThemeQuery.parse("") == [:])
    }

    @Test("Axes are separated by commas and pinned with a colon")
    func parsesColonForm() throws {
        #expect(try ThemeQuery.parse("Mode:Dark,Base:Slate") == ["Mode": "Dark", "Base": "Slate"])
    }

    @Test("The CLI's equals form is accepted too, so one spelling is never wrong")
    func parsesEqualsForm() throws {
        #expect(try ThemeQuery.parse("Mode=Dark,Base=Slate") == ["Mode": "Dark", "Base": "Slate"])
    }

    @Test("Surrounding whitespace is trimmed from both halves")
    func trimsWhitespace() throws {
        #expect(try ThemeQuery.parse(" Mode : Dark ") == ["Mode": "Dark"])
    }

    @Test("A pin with no separator is an error naming the pin, never a silent no-op")
    func rejectsMalformedPins() {
        #expect(throws: ViewerError.malformedTheme("Dark")) {
            try ThemeQuery.parse("Mode:Dark,Dark")
        }
    }

    @Test("A pin with an empty axis or value is an error")
    func rejectsEmptyHalves() {
        #expect(throws: ViewerError.self) { try ThemeQuery.parse(":Dark") }
        #expect(throws: ViewerError.self) { try ThemeQuery.parse("Mode:") }
    }

    @Test("A parsed selection renders back to the canonical colon form for cache keys")
    func rendersCanonically() {
        #expect(ThemeQuery.canonical(["Mode": "Dark", "Base": "Slate"]) == "Base:Slate,Mode:Dark")
        #expect(ThemeQuery.canonical([:]) == "")
    }
}
