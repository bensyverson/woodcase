//
//  RouteTests.swift
//  WoodcaseViewerTests
//

import Foundation
import Testing
@testable import WoodcaseViewer

struct RouteTests {
    @Test("A literal pattern matches only itself")
    func matchesLiterals() {
        let route = Route(.get, "/files")
        #expect(route.match(path: "/files") == [:])
        #expect(route.match(path: "/files/") == [:])
        #expect(route.match(path: "/file") == nil)
        #expect(route.match(path: "/files/a1") == nil)
    }

    @Test("A whole-segment parameter captures that segment by name")
    func capturesParameters() {
        let route = Route(.get, "/files/{file}/tree.json")
        #expect(route.match(path: "/files/a1b2/tree.json") == ["file": "a1b2"])
        #expect(route.match(path: "/files/a1b2/activity.json") == nil)
        #expect(route.match(path: "/files//tree.json") == nil)
    }

    @Test("A parameter may carry a literal suffix, so an extension can select the format")
    func capturesParameterWithSuffix() {
        let route = Route(.get, "/files/{file}/artboards/{artboard}.png")
        #expect(route.match(path: "/files/a1/artboards/Cnv01.png")
            == ["file": "a1", "artboard": "Cnv01"])
        // The suffix is required, and is not swallowed by the parameter.
        #expect(route.match(path: "/files/a1/artboards/Cnv01") == nil)
        #expect(route.match(path: "/files/a1/artboards/.png") == nil)
    }

    @Test("The root pattern matches the root path")
    func matchesRoot() {
        #expect(Route(.get, "/").match(path: "/") == [:])
        #expect(Route(.get, "/").match(path: "/files") == nil)
    }

    @Test("A literal beats a suffixed parameter, which beats a bare parameter")
    func ranksSegmentsByHowNarrowlyTheyMatch() {
        let literal = Route(.get, "/files/{file}/artboards/still.png").specificity
        let suffixed = Route(.get, "/files/{file}/artboards/{artboard}.png").specificity
        let bare = Route(.get, "/files/{file}/artboards/{artboard}").specificity
        #expect(literal > suffixed)
        #expect(suffixed > bare)
        #expect(literal > bare)
    }

    @Test("The first segment that differs decides, left to right")
    func comparesSegmentsLeftToRight() {
        // The second pattern is literal in two later segments and still loses: the first
        // segment that differs is its own, and there it captures.
        let early = Route(.get, "/files/{a}/{b}").specificity
        let late = Route(.get, "/{a}/tree/leaf").specificity
        #expect(early > late)
    }

    @Test("Patterns of the same shape are equally specific, whatever they name")
    func equalShapesAreEquallySpecific() {
        #expect(Route(.get, "/files/{file}").specificity == Route(.get, "/pages/{page}").specificity)
        #expect(Route(.get, "/f/{a}.png").specificity == Route(.get, "/f/{b}.json").specificity)
    }

    @Test("A route is identified by its method and pattern")
    func isIdentifiedByMethodAndPattern() {
        #expect(Route(.get, "/files") == Route(.get, "/files"))
        #expect(Route(.get, "/files") != Route(.head, "/files"))
        #expect(Route(.get, "/files") != Route(.get, "/events"))
    }
}
