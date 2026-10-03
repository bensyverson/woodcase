//
//  PenImageFillModeAuthoringTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// Leniency is for reading files: an agent's write (`set`, a batch line) that names an image
/// mode this build does not know is refused with the modes it could have written, while 2.19's
/// `fill` and `fit` are still taken and written in their 2.20 spelling.
struct PenImageFillModeAuthoringTests {
    /// A frame to write fills onto.
    private func frame() -> PenNode {
        PenNode(
            id: "f1",
            common: PenNodeCommon(name: "Card"),
            kind: .frame(PenNode.FrameData(width: .fixed(100), height: .fixed(60)))
        )
    }

    /// A fill list with one image paint of `mode`, as the command line would type it.
    private func imageFills(mode: String) throws -> AnyCodable {
        let text = #"[{"type":"image","url":"a.png","mode":"\#(mode)"}]"#
        return try JSONDecoder().decode(AnyCodable.self, from: Data(text.utf8))
    }

    /// Writes `value` to `kind.fills` the way the batch planner does: checked as authored, then set.
    private func write(_ value: AnyCodable) throws -> PenNode {
        try NodePropertyCodec.checkAuthored(["kind.fills": value], on: frame())
        return try NodePropertyCodec.setting(value, at: "kind.fills", on: frame())
    }

    @Test("An authored unknown mode is refused, naming it and the three modes")
    func unknownModeIsRefused() throws {
        do {
            _ = try write(imageFills(mode: "cove"))
            Issue.record("an unknown image mode was accepted in an authored write")
        } catch let error as EditingError {
            guard case let .propertyTypeMismatch(_, _, _, actual) = error else {
                Issue.record("expected a type mismatch, got \(error)")
                return
            }
            #expect(actual.contains("[0].mode"), "the refusal does not locate the mode: \(actual)")
            #expect(actual.contains(#""cove""#), "the refusal does not name the spelling: \(actual)")
            for mode in ["cover", "contain", "stretch"] {
                #expect(actual.contains(#""\#(mode)""#), "the refusal does not offer \(mode): \(actual)")
            }
        }
    }

    @Test("An authored decode refuses an unknown mode")
    func authoringDecodeRefusesUnknownMode() {
        let decoder = JSONDecoder()
        decoder.userInfo[PenDecodingMode.userInfoKey] = PenDecodingMode.authoring
        #expect(throws: DecodingError.self) {
            try decoder.decode(PenFill.self, from: Data(#"{"type":"image","mode":"cove"}"#.utf8))
        }
    }

    @Test("An authored legacy fit is taken and written as contain")
    func legacyFitIsWrittenAsContain() throws {
        let node = try write(imageFills(mode: "fit"))
        guard case let .frame(data) = node.kind, case let .image(image)? = data.fills?.all.first else {
            Issue.record("the image fill was not written")
            return
        }
        #expect(image.mode == .contain)
        let encoded = try String(decoding: JSONEncoder().encode(image), as: UTF8.self)
        #expect(encoded.contains(#""mode":"contain""#))
    }

    @Test("Reading a file still keeps an unknown mode")
    func fileDecodeKeepsUnknownMode() throws {
        let fill = try JSONDecoder().decode(PenFill.self, from: Data(#"{"type":"image","mode":"cove"}"#.utf8))
        guard case let .image(image) = fill else {
            Issue.record("expected an image fill")
            return
        }
        #expect(image.mode == .unknown("cove"))
    }
}
