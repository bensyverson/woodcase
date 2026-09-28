//
//  NodeAddressTests.swift
//  WoodcaseTests
//

import Foundation
import Testing
@testable import Woodcase

struct NodeAddressTests {
    // MARK: - Parsing

    @Test("A bare segment parses to a single-segment path")
    func bareSegment() throws {
        let address = try #require(NodeAddress("ALu8G"))
        #expect(address == .path(["ALu8G"]))
        #expect(address.isBare)
        #expect(address.segments == ["ALu8G"])
        #expect(address.tagName == nil)
    }

    @Test("A slash path parses to its segments")
    func slashPath() throws {
        let address = try #require(NodeAddress("Dashboard/Header/Title"))
        #expect(address == .path(["Dashboard", "Header", "Title"]))
        #expect(!address.isBare)
    }

    @Test("A leading @ parses to a tag")
    func tag() throws {
        let address = try #require(NodeAddress("@hero"))
        #expect(address == .tag(name: "hero", path: []))
        #expect(address.tagName == "hero")
        #expect(address.segments == nil)
    }

    @Test("An @ only counts as a tag at the head of the address")
    func atInsidePath() throws {
        let address = try #require(NodeAddress("Card/@hero"))
        #expect(address == .path(["Card", "@hero"]))
    }

    @Test("An id-forcing segment keeps its marker")
    func markerSegment() throws {
        let address = try #require(NodeAddress("Dashboard/#uKX6O"))
        #expect(address == .path(["Dashboard", "#uKX6O"]))
    }

    @Test(
        "Malformed addresses do not parse",
        arguments: ["", "/", "/Header", "Header/", "Dashboard//Title", "@", "@a/", "@/b", "#"]
    )
    func malformed(raw: String) {
        #expect(NodeAddress(raw) == nil)
    }

    // MARK: - Rendering

    @Test("An address round-trips through its string form", arguments: [
        "ALu8G", "Dashboard/Header/Title", "@hero", "@hero/Title", "#uKX6O", "Card/@hero",
    ])
    func stringRoundTrip(raw: String) throws {
        let address = try #require(NodeAddress(raw))
        #expect(address.description == raw)
        #expect(NodeAddress(address.description) == address)
    }

    @Test("The unnamed marker is the id behind the id-forcing prefix")
    func unnamedMarker() {
        #expect(NodeAddress.marker(forID: "uKX6O") == "#uKX6O")
    }

    // MARK: - Codable

    @Test("An address encodes as its string form")
    func codable() throws {
        let address = NodeAddress.path(["Dashboard", "Title"])
        let data = try JSONEncoder().encode(address)
        #expect(try JSONDecoder().decode(NodeAddress.self, from: data) == address)

        let literal = Data(#""Dashboard/Title""#.utf8)
        #expect(try JSONDecoder().decode(NodeAddress.self, from: literal) == address)
    }

    @Test("Decoding a malformed address fails")
    func codableRejectsMalformed() {
        let data = Data(#""Dashboard//Title""#.utf8)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(NodeAddress.self, from: data)
        }
    }
}
