//
//  DecodingReasonTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// `DecodingError` says everything and reads like nothing: the type it wanted is in
/// one field, the key in another, and `localizedDescription` throws all of it away for
/// "The data couldn't be read because it isn't in the correct format." These tests pin
/// the clause a reader is given instead.
@Suite("DecodingReason")
struct DecodingReasonTests {
    /// A stand-in for the document shape, so the errors under test are the ones
    /// Foundation really throws rather than ones assembled by hand.
    private struct Document: Decodable {
        struct Child: Decodable {
            let id: String
            let width: Double
        }

        let version: String
        let children: [Child]
    }

    /// Raised when a sample this suite expects to be rejected decodes cleanly.
    private struct DecodedUnexpectedly: Error {}

    /// Decodes `json` as ``Document`` and returns the failure it produced.
    private func failure(_ json: String) throws -> any Error {
        do {
            _ = try JSONDecoder().decode(Document.self, from: Data(json.utf8))
        } catch {
            return error
        }
        throw DecodedUnexpectedly()
    }

    // MARK: - Bytes that are not JSON

    @Test("Bytes that are not JSON say exactly that, and nothing else")
    func notJSON() throws {
        let reason = try DecodingReason.describe(failure("not json at all"))
        #expect(reason == "The given data was not valid JSON")
    }

    // MARK: - A key that is missing

    @Test("A missing key at the root names the document and the key")
    func missingKeyAtRoot() throws {
        let reason = try DecodingReason.describe(failure(#"{"children": []}"#))
        #expect(reason == #"the document has no "version""#)
    }

    @Test("A missing key inside an array names its path")
    func missingKeyInsideArray() throws {
        let reason = try DecodingReason.describe(
            failure(#"{"version": "2.17", "children": [{"width": 3}]}"#)
        )
        #expect(reason == #"children[0] has no "id""#)
    }

    @Test("What the root is called is the caller's to choose")
    func rootIsNameable() throws {
        let reason = try DecodingReason.describe(failure(#"{"children": []}"#), root: "the line")
        #expect(reason == #"the line has no "version""#)
    }

    // MARK: - A key of the wrong type

    @Test("A key of the wrong type names the path and the type wanted")
    func wrongTypeIsNamed() throws {
        let reason = try DecodingReason.describe(failure(#"{"version": 2, "children": []}"#))
        #expect(reason == "version should be a string")
    }

    @Test("A key of the wrong type deep in the tree keeps its index")
    func wrongTypeDeepInTheTree() throws {
        let reason = try DecodingReason.describe(
            failure(#"{"version": "2.17", "children": [{"id": 5, "width": 3}]}"#)
        )
        #expect(reason == "children[0].id should be a string")
    }

    @Test("A number is called a number, whatever Swift type it decodes to")
    func numbersAreNumbers() throws {
        let reason = try DecodingReason.describe(
            failure(#"{"version": "2.17", "children": [{"id": "a", "width": "wide"}]}"#)
        )
        #expect(reason == "children[0].width should be a number")
    }

    @Test("A document that is not an object at all says so")
    func rootOfTheWrongType() throws {
        let reason = try DecodingReason.describe(failure("[]"))
        #expect(reason == "the document should be an object")
    }

    // MARK: - A key that is null

    @Test("A null where a value belongs says what was required")
    func nullValue() throws {
        let reason = try DecodingReason.describe(failure(#"{"version": null, "children": []}"#))
        #expect(reason == "version is null, but a string is required")
    }

    // MARK: - A decoder of our own refusing

    @Test("A hand-thrown refusal keeps its own sentence, under its path")
    func dataCorruptedUnderAPath() {
        let error = DecodingError.dataCorrupted(
            DecodingError.Context(
                codingPath: [PathKey("children"), PathKey(index: 2), PathKey("type")],
                debugDescription: "Unknown node type \"blob\"."
            )
        )
        #expect(DecodingReason.describe(error) == #"children[2].type: Unknown node type "blob""#)
    }

    // MARK: - Anything else

    @Test("An error that is not a decoding error keeps its own description")
    func nonDecodingError() {
        let error = CocoaError(.fileReadNoSuchFile)
        #expect(DecodingReason.describe(error) == error.localizedDescription)
    }

    /// A coding key for a hand-built context.
    private struct PathKey: CodingKey {
        init(_ stringValue: String) {
            self.stringValue = stringValue
            intValue = nil
        }

        init(index: Int) {
            stringValue = "Index \(index)"
            intValue = index
        }

        init?(stringValue: String) {
            self.init(stringValue)
        }

        init?(intValue: Int) {
            self.init(index: intValue)
        }

        let stringValue: String
        let intValue: Int?
    }
}
