import Foundation
import Testing
@testable import Woodcase

struct NodeOverridesTests {
    @Test("Default init produces all-nil overrides")
    func defaultInit() {
        let overrides = NodeOverrides()
        #expect(overrides.x == nil)
        #expect(overrides.y == nil)
        #expect(overrides.width == nil)
        #expect(overrides.height == nil)
        #expect(overrides.rotation == nil)
        #expect(overrides.opacity == nil)
        #expect(overrides.enabled == nil)
        #expect(overrides.fills == nil)
    }

    @Test("Codable round-trip preserves values")
    func codableRoundTrip() throws {
        let original = NodeOverrides(
            x: 10, y: 20,
            width: 100, height: 50,
            rotation: 45, opacity: 0.5,
            enabled: false
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NodeOverrides.self, from: data)
        #expect(decoded == original)
    }

    @Test("Equatable works correctly")
    func equatable() {
        let a = NodeOverrides(x: 10, opacity: 0.5)
        let b = NodeOverrides(x: 10, opacity: 0.5)
        let c = NodeOverrides(x: 20, opacity: 0.5)
        #expect(a == b)
        #expect(a != c)
    }

    @Test("Hashable works correctly")
    func hashable() {
        let a = NodeOverrides(x: 10, opacity: 0.5)
        let b = NodeOverrides(x: 10, opacity: 0.5)
        #expect(a.hashValue == b.hashValue)
    }
}
