import Foundation
import Testing
@testable import Woodcase

/// Every `geometry` string in the test fixtures, put through the writer and the anchor
/// model: the property the pen tool leans on, checked over paths drawn by Pen, Figma
/// imports and hand-written fixtures rather than only over examples written for the test.
struct PenPathFixtureRoundTripTests {
    /// Every `geometry` string value anywhere in a `.pen` fixture, with the file it came from.
    private static func fixtureGeometries() throws -> [(file: String, data: String)] {
        let root = try #require(Bundle.module.url(forResource: "Fixtures", withExtension: nil))
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil)?
            .compactMap { $0 as? URL }
            .filter { $0.pathExtension == "pen" } ?? []
        var found: [(file: String, data: String)] = []
        for file in files {
            guard let data = try? Data(contentsOf: file),
                  let json = try? JSONSerialization.jsonObject(with: data) else { continue }
            collect(json, file: file.lastPathComponent, into: &found)
        }
        return found
    }

    private static func collect(_ json: Any, file: String, into found: inout [(file: String, data: String)]) {
        if let object = json as? [String: Any] {
            for (key, value) in object {
                if key == "geometry", let data = value as? String {
                    found.append((file, data))
                } else {
                    collect(value, file: file, into: &found)
                }
            }
        } else if let array = json as? [Any] {
            for value in array {
                collect(value, file: file, into: &found)
            }
        }
    }

    @Test("Any parsed fixture path re-serializes to geometry that parses back equal")
    func reserializes() throws {
        let geometries = try Self.fixtureGeometries()
        var parsedCount = 0
        for (file, data) in geometries {
            guard let path = PenPath(svg: data) else { continue }
            parsedCount += 1
            let written = path.svgPathData
            #expect(PenPath(svg: written) == path, "\(file): \(data) wrote \(written)")
        }
        #expect(parsedCount >= 40, "the corpus should hold the fixtures' paths; parsed \(parsedCount)")
    }

    @Test("Any parsed fixture path's anchors convert to geometry and back unchanged")
    func anchorsAreStable() throws {
        for (file, data) in try Self.fixtureGeometries() {
            guard let path = PenPath(svg: data) else { continue }
            let contours = path.contours
            let geometry = PenPath(contours: contours).svgPathData
            let reread = try #require(PenPath(svg: geometry), "\(file): \(data) wrote \(geometry)")
            #expect(reread.contours == contours, "\(file): \(data)")
        }
    }
}
