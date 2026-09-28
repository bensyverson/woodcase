import Testing
@testable import WoodcaseCommandCore

struct ThemeCombinationTests {
    // MARK: - Pin Parsing

    @Test("Parses comma-separated key=value pins")
    func parsePins() throws {
        let pins = try ThemePinParser.parse("mode=dark,platform=ios")
        #expect(pins == ["mode": "dark", "platform": "ios"])
    }

    @Test("Parses single pin")
    func parseSinglePin() throws {
        let pins = try ThemePinParser.parse("mode=dark")
        #expect(pins == ["mode": "dark"])
    }

    @Test("Returns empty for nil input")
    func parseNil() throws {
        let pins = try ThemePinParser.parse(nil)
        #expect(pins.isEmpty)
    }

    @Test("Throws on malformed pin without equals sign")
    func parseMalformed() {
        #expect(throws: ThemePinParser.PinError.self) {
            try ThemePinParser.parse("modedark")
        }
    }

    // MARK: - Cartesian Product

    @Test("Two axes with two options each produces four combinations")
    func twoByTwo() {
        let themes: [String: [String]] = [
            "mode": ["light", "dark"],
            "platform": ["ios", "web"],
        ]
        let combos = ThemeCombination.allCombinations(from: themes, pins: [:])
        #expect(combos.count == 4)
        #expect(combos.contains(["mode": "light", "platform": "ios"]))
        #expect(combos.contains(["mode": "light", "platform": "web"]))
        #expect(combos.contains(["mode": "dark", "platform": "ios"]))
        #expect(combos.contains(["mode": "dark", "platform": "web"]))
    }

    @Test("Pinning one axis reduces combinations")
    func pinnedAxis() {
        let themes: [String: [String]] = [
            "mode": ["light", "dark"],
            "platform": ["ios", "web"],
        ]
        let combos = ThemeCombination.allCombinations(from: themes, pins: ["mode": "dark"])
        #expect(combos.count == 2)
        #expect(combos.allSatisfy { $0["mode"] == "dark" })
    }

    @Test("Fully pinned produces single combination")
    func fullyPinned() {
        let themes: [String: [String]] = [
            "mode": ["light", "dark"],
            "platform": ["ios", "web"],
        ]
        let combos = ThemeCombination.allCombinations(
            from: themes,
            pins: ["mode": "dark", "platform": "ios"]
        )
        #expect(combos == [["mode": "dark", "platform": "ios"]])
    }

    @Test("Nil themes produces single empty combination")
    func nilThemes() {
        let combos = ThemeCombination.allCombinations(from: nil, pins: [:])
        #expect(combos == [[:]])
    }

    @Test("Empty themes produces single empty combination")
    func emptyThemes() {
        let combos = ThemeCombination.allCombinations(from: [:], pins: [:])
        #expect(combos == [[:]])
    }

    // MARK: - Subdirectory Naming

    @Test("Subdirectory name joins sorted axis values with hyphen")
    func subdirectoryName() {
        let combo: [String: String] = ["mode": "dark", "platform": "ios"]
        #expect(ThemeCombination.subdirectoryName(for: combo) == "dark-ios")
    }

    @Test("Single axis uses just the value")
    func singleAxisSubdir() {
        let combo = ["mode": "dark"]
        #expect(ThemeCombination.subdirectoryName(for: combo) == "dark")
    }

    @Test("Empty combination returns nil")
    func emptyComboSubdir() {
        #expect(ThemeCombination.subdirectoryName(for: [:]) == nil)
    }

    @Test("Values with unsafe filesystem characters are sanitized")
    func sanitizedSubdir() {
        let combo = ["mode": "light/bright"]
        #expect(ThemeCombination.subdirectoryName(for: combo) == "light-bright")
    }

    // MARK: - Frame Theme Matching

    @Test("Frame with nil theme matches every combination")
    func nilThemeMatchesAll() {
        let combo = ["mode": "dark"]
        #expect(ThemeCombination.frameMatches(theme: nil, combination: combo))
    }

    @Test("Frame with empty theme matches every combination")
    func emptyThemeMatchesAll() {
        let combo = ["mode": "dark"]
        #expect(ThemeCombination.frameMatches(theme: [:], combination: combo))
    }

    @Test("Frame with nil theme matches every combination of a multi-axis document")
    func nilThemeMatchesEveryMultiAxisCombination() {
        let combos = ThemeCombination.allCombinations(
            from: ["mode": ["light", "dark"], "platform": ["ios", "web"]],
            pins: [:]
        )
        #expect(combos.count == 4)
        #expect(combos.allSatisfy { combo in
            ThemeCombination.frameMatches(theme: nil, combination: combo)
        })
    }

    @Test("Frame theme matches when all entries match the combination")
    func exactMatch() {
        let frameTheme = ["mode": "dark"]
        let combo = ["mode": "dark", "platform": "ios"]
        #expect(ThemeCombination.frameMatches(theme: frameTheme, combination: combo))
    }

    @Test("Frame theme does not match when a value differs")
    func mismatch() {
        let frameTheme = ["mode": "dark"]
        let combo = ["mode": "light", "platform": "ios"]
        #expect(!ThemeCombination.frameMatches(theme: frameTheme, combination: combo))
    }

    @Test("Frame with multi-axis theme must match all axes")
    func multiAxisMatch() {
        let frameTheme = ["mode": "dark", "platform": "ios"]
        let comboMatch = ["mode": "dark", "platform": "ios"]
        let comboMismatch = ["mode": "dark", "platform": "web"]
        #expect(ThemeCombination.frameMatches(theme: frameTheme, combination: comboMatch))
        #expect(!ThemeCombination.frameMatches(theme: frameTheme, combination: comboMismatch))
    }

    @Test("Frame theme matches empty combination only when theme is nil or empty")
    func emptyCombo() {
        #expect(ThemeCombination.frameMatches(theme: nil, combination: [:]))
        #expect(ThemeCombination.frameMatches(theme: [:], combination: [:]))
        #expect(!ThemeCombination.frameMatches(theme: ["mode": "dark"], combination: [:]))
    }
}
