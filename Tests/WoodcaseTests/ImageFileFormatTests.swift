//
//  ImageFileFormatTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `ImageFileFormat` names an image file's format from its leading bytes.
struct ImageFileFormatTests {
    @Test("Each format is known by its signature", arguments: [
        ([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A], ImageFileFormat.png),
        ([0xFF, 0xD8, 0xFF, 0xE0], .jpeg),
        (Array("GIF89a".utf8), .gif),
        (Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WEBPVP8 ".utf8), .webp),
    ] as [([UInt8], ImageFileFormat)])
    func sniffs(bytes: [UInt8], format: ImageFileFormat) {
        #expect(ImageFileFormat(sniffing: Data(bytes)) == format)
    }

    @Test("Other bytes are no format: a RIFF that is not WebP, text, too few bytes", arguments: [
        Array("RIFF".utf8) + [0, 0, 0, 0] + Array("WAVEfmt ".utf8),
        Array("<html>".utf8),
        [0x89, 0x50],
    ])
    func unknown(bytes: [UInt8]) {
        #expect(ImageFileFormat(sniffing: Data(bytes)) == nil)
    }

    @Test("Each format has its usual extension")
    func extensions() {
        #expect(ImageFileFormat.allCases.map(\.fileExtension) == ["png", "jpg", "gif", "webp"])
    }
}
