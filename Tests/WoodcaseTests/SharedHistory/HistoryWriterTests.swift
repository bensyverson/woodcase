//
//  HistoryWriterTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

/// A writer is an identity on one device, named so it is a safe file name everywhere a
/// bundle travels.
struct HistoryWriterTests {
    @Test("a writer is identity@device, lowercased")
    func joinsIdentityAndDevice() {
        let writer = HistoryWriter(identity: "Ben", device: "Grace")

        #expect(writer.rawValue == "ben@grace")
        #expect(writer.fileName == "ben@grace.jsonl")
    }

    @Test("spaces, punctuation and accents become a safe name")
    func sanitizesPunctuationAndAccents() {
        let writer = HistoryWriter(identity: "José Núñez", device: "Ben's MacBook Pro")

        #expect(writer.rawValue == "jose-nunez@ben-s-macbook-pro")
    }

    @Test("dots and slashes can never name another file")
    func sanitizesPathCharacters() {
        let writer = HistoryWriter(identity: "../etc/passwd", device: "grace.local")

        #expect(writer.rawValue == "etc-passwd@grace-local")
        #expect(!writer.fileName.dropLast(".jsonl".count).contains("."))
        #expect(!writer.fileName.contains("/"))
    }

    @Test("the unattributed writer has a name")
    func namesTheUnattributedWriter() {
        #expect(HistoryWriter(identity: ActivityEvent.unattributed, device: "grace").rawValue == "unattributed@grace")
    }

    @Test("a name with no Latin letters is transliterated or hashed, never empty")
    func neverEmpty() {
        let han = HistoryWriter(identity: "李", device: "grace")
        let paint = HistoryWriter(identity: "🎨", device: "grace")
        let brush = HistoryWriter(identity: "🖌️", device: "grace")

        #expect(han.rawValue == "li@grace")
        #expect(!paint.identity.isEmpty)
        #expect(paint.identity != brush.identity)
        #expect(HistoryWriter(fileStem: paint.rawValue) == paint)
    }

    @Test("each part is at most 64 characters")
    func capsLength() {
        let writer = HistoryWriter(identity: String(repeating: "a", count: 200), device: "grace")

        #expect(writer.identity.count == 64)
    }

    @Test("a file stem reads back as the writer that wrote it")
    func parsesFileStems() {
        #expect(HistoryWriter(fileStem: "ben@grace") == HistoryWriter(identity: "ben", device: "grace"))
        #expect(HistoryWriter(fileStem: "activity") == nil)
        #expect(HistoryWriter(fileStem: "ben@grace.20260101T000000Z") == nil)
        #expect(HistoryWriter(fileStem: "Ben@grace") == nil)
        #expect(HistoryWriter(fileStem: "ben@") == nil)
    }

    @Test("$WOODCASE_DEVICE names the device, else this machine's name")
    func resolvesTheDevice() {
        #expect(HistoryWriter.currentDevice(environment: [HistoryWriter.deviceEnvironmentVariable: "Hopper"]) == "hopper")
        let machine = HistoryWriter.currentDevice(environment: [:])
        #expect(!machine.isEmpty)
        #expect(HistoryWriter(identity: "ben", device: machine).device == machine)
    }
}
