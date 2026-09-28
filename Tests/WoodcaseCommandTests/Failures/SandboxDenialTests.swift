//
//  SandboxDenialTests.swift
//  WoodcaseCommandTests
//

import Foundation
import Testing
import Woodcase
@testable import WoodcaseCommandCore

@Suite("SandboxDenial")
struct SandboxDenialTests {
    // MARK: - Raw POSIX errors

    @Test("Recognises EPERM as a POSIXError")
    func recognisesPOSIXEPERM() {
        #expect(SandboxDenial.matches(POSIXError(.EPERM)))
    }

    @Test("Recognises EACCES as a POSIXError")
    func recognisesPOSIXEACCES() {
        #expect(SandboxDenial.matches(POSIXError(.EACCES)))
    }

    @Test("Does not mistake an unrelated POSIX error for a sandbox denial")
    func ignoresUnrelatedPOSIXError() {
        #expect(!SandboxDenial.matches(POSIXError(.ENOENT)))
    }

    // MARK: - Errors that carry only rendered text

    @Test("Falls back to the rendered text for an error with no raw errno, like PenFileError")
    func recognisesPenFileErrorText() {
        let error = PenFileError.cannotOpen(
            url: URL(fileURLWithPath: "/tmp/x"), reason: "Operation not permitted"
        )
        #expect(SandboxDenial.matches(error))
    }

    @Test("Recognises Permission denied text too")
    func recognisesPermissionDeniedText() {
        let error = PenFileError.writeFailed(
            url: URL(fileURLWithPath: "/tmp/x"), reason: "Permission denied"
        )
        #expect(SandboxDenial.matches(error))
    }

    @Test("An ordinary PenFileError is not a sandbox denial")
    func ignoresOrdinaryPenFileError() {
        let error = PenFileError.cannotOpen(
            url: URL(fileURLWithPath: "/tmp/x"), reason: "No such file or directory"
        )
        #expect(!SandboxDenial.matches(error))
    }

    // MARK: - The sentence

    @Test("The sentence names the restriction and the remedy")
    func sentenceNamesRemedy() {
        let sentence = SandboxDenial.sentence(forbidding: "listening on a port")
        #expect(sentence.contains("listening on a port"))
        #expect(sentence.lowercased().contains("sandbox"))
        #expect(sentence.lowercased().contains("disabled"))
    }
}
