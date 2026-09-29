//
//  SwiftUIAPIScanner+Declarations.swift
//  WoodcaseTests
//

import Woodcase

extension SwiftUIAPIScanner {
    /// What a body of emitted Swift declares for itself: the names a use of which is the
    /// code's own, not the SDK's.
    ///
    /// A name counts as the code's own only where its use could reach that declaration: a
    /// call to a declared function, an implicit member naming a declared case or static,
    /// a value member naming a declared property. So a declared `var frame` does not hide a
    /// call to SwiftUI's `.frame(width:)`, nor a declared `var center` an implicit `.center`.
    struct Declarations: Friendly {
        /// Types, protocols and generic parameters: `PenGradient`, `S`.
        var types: Set<String> = []

        /// Functions and methods: `penFont`, `path`.
        var functions: Set<String> = []

        /// Properties, locals, parameters (both names) and closure parameters.
        var values: Set<String> = []

        /// Enum cases and static members: what an implicit `.name` can reach.
        var statics: Set<String> = []

        /// The external labels of every declared initializer, `_` for an unlabeled
        /// parameter: `[["hex", "opacity"]]` for `init(hex: UInt32, opacity: Double = 1)`.
        var initializers: [[String]] = []

        /// The declarations in `code` (the output of ``SwiftUIAPIScanner/code(_:)``).
        init(_ code: String) {
            let chars = Array(code)
            var index = 0
            while index < chars.count {
                guard isIdentifierHead(chars[index]), index == 0 || !isIdentifierBody(chars[index - 1]) else {
                    index += 1
                    continue
                }
                let start = index
                let keyword = Self.word(chars, at: start)
                index += keyword.count
                if start > 0, chars[start - 1] == "." { continue }
                switch keyword {
                case "struct", "enum", "class", "protocol", "typealias", "actor", "associatedtype":
                    let name = Self.nextWord(chars, from: index)
                    types.insert(name)
                    types.formUnion(Self.genericParameters(chars, after: name, from: index))
                case "func":
                    let name = Self.nextWord(chars, from: index)
                    functions.insert(name)
                    types.formUnion(Self.genericParameters(chars, after: name, from: index))
                    values.formUnion(Self.parameters(chars, from: index).flatMap(\.self))
                case "init":
                    guard let open = Self.nextNonSpace(chars, from: index), chars[open] == "(" else { continue }
                    let parameters = Self.parameters(chars, from: index)
                    initializers.append(parameters.map { $0.first ?? "_" })
                    values.formUnion(parameters.flatMap(\.self))
                case "var", "let":
                    values.formUnion(Self.boundNames(chars, from: index))
                    if Self.previousWord(chars, before: start) == "static" {
                        statics.formUnion(Self.boundNames(chars, from: index))
                    }
                case "case":
                    statics.formUnion(Self.caseNames(chars, from: index))
                case "in":
                    values.formUnion(Self.closureParameters(chars, before: start))
                case "for":
                    values.formUnion(Self.boundNames(chars, from: index))
                default:
                    break
                }
            }
            // A tuple's element labels and a parameter's names: `name: Type`.
            for label in code.matches(of: #/\b([a-z_]\w*)\s*:\s*(?:@\w+\s+)*(?:inout\s+)?[A-Z(\[]/#) {
                let name = String(label.output.1)
                if !(name.hasPrefix("kCT") || name.hasPrefix("kCG")) { values.insert(name) }
            }
            values.remove("_")
        }

        /// Whether `use` reaches something this code declares.
        func declares(_ use: SwiftUIAPIUse) -> Bool {
            let name = use.name
            if use.isCapitalized, types.contains(name) { return true }
            // `theme.brand`: the emitted `PenTheme`'s property for a document variable, which
            // the package's theme file declares and a page's golden does not hold.
            if use.receiver == "theme", use.labels == nil { return true }
            if name == "init", let labels = use.labels {
                // `self.init(title:content:)` in a convenience initializer.
                return initializers.contains { SwiftUIVocabulary.fits(labels, trailing: use.trailingClosures, into: $0) }
            }
            switch (use.access, use.labels) {
            case (.bare, .some):
                if use.isCapitalized {
                    // An initializer the code adds to an SDK type: `Color(hex:)`.
                    guard let labels = use.labels, labels.contains(where: { $0 != "_" }) else { return false }
                    return initializers.contains { SwiftUIVocabulary.fits(labels, trailing: use.trailingClosures, into: $0) }
                }
                return functions.contains(name) || values.contains(name)
            case (.qualified, .some):
                // `if configuration.isOn {` reads as a trailing closure.
                return functions.contains(name) || (use.labels == [] && use.trailingClosures == 1 && values.contains(name))
            case (.implicit, .some):
                // A case with a payload, `.unknown("x")`; and `.selected {` in
                // `if state == .selected {` reads as a trailing closure.
                return functions.contains(name) || statics.contains(name)
            case (.implicit, nil):
                return statics.contains(name)
            case (.qualified, nil), (.keyPath, nil):
                return values.contains(name) || statics.contains(name) || functions.contains(name)
            default:
                return false
            }
        }

        // MARK: - Reading declarations

        private static func word(_ chars: [Character], at index: Int) -> String {
            var end = index
            while end < chars.count, isIdentifierBody(chars[end]) {
                end += 1
            }
            return String(chars[index ..< end])
        }

        private static func nextNonSpace(_ chars: [Character], from index: Int) -> Int? {
            var next = index
            while next < chars.count, chars[next] == " " || chars[next] == "\t" {
                next += 1
            }
            return next < chars.count ? next : nil
        }

        private static func nextWord(_ chars: [Character], from index: Int) -> String {
            guard let start = nextNonSpace(chars, from: index), isIdentifierHead(chars[start]) else { return "" }
            return word(chars, at: start)
        }

        private static func previousWord(_ chars: [Character], before index: Int) -> String {
            var end = index
            while end > 0, chars[end - 1] == " " || chars[end - 1] == "\t" {
                end -= 1
            }
            var start = end
            while start > 0, isIdentifierBody(chars[start - 1]) {
                start -= 1
            }
            return String(chars[start ..< end])
        }

        /// The generic parameters of `name`, declared from `index`: `S` in `PenBox<S: Shape>`.
        private static func genericParameters(_ chars: [Character], after name: String, from index: Int) -> [String] {
            guard let start = nextNonSpace(chars, from: index), start + name.count < chars.count,
                  chars[start + name.count] == "<" else { return [] }
            var end = start + name.count
            while end < chars.count, chars[end] != ">" {
                end += 1
            }
            return String(chars[(start + name.count + 1) ..< end]).split(separator: ",").compactMap {
                $0.split(separator: ":").first.map(Self.trimmed)
            }
        }

        /// Each parameter's names (external, then internal) of the first argument list
        /// after `index`: `[["_", "shape"], ["color", "c"]]`.
        private static func parameters(_ chars: [Character], from index: Int) -> [[String]] {
            var open = index
            while open < chars.count, chars[open] != "(", chars[open] != "{", chars[open] != "\n" {
                open += 1
            }
            guard open < chars.count, chars[open] == "(" else { return [] }
            var depth = 0
            var segments: [String] = []
            var segment = ""
            for (offset, c) in chars[open...].enumerated() {
                let isArrow = c == ">" && offset > 0 && chars[open + offset - 1] == "-"
                if "([<".contains(c) { depth += 1 }
                if ")]>".contains(c), !isArrow { depth -= 1 }
                if depth == 0 { break }
                if c == ",", depth == 1 {
                    segments.append(segment)
                    segment = ""
                } else if depth >= 1, !(depth == 1 && c == "(") {
                    segment.append(c)
                }
            }
            segments.append(segment)
            return segments.compactMap { segment in
                guard let colon = segment.firstIndex(of: ":") else { return nil }
                let names = segment[..<colon].split(separator: " ").map(String.init).filter { !$0.hasPrefix("@") }
                return names.isEmpty ? nil : names
            }
        }

        /// The names a `var`, `let` or `for` binds: `x`, or each of `(a, b)`.
        private static func boundNames(_ chars: [Character], from index: Int) -> [String] {
            guard let start = nextNonSpace(chars, from: index) else { return [] }
            if chars[start] == "(" {
                var end = start
                while end < chars.count, chars[end] != ")" {
                    end += 1
                }
                return String(chars[(start + 1) ..< end]).split(separator: ",").map(Self.trimmed)
            }
            return isIdentifierHead(chars[start]) ? [word(chars, at: start)] : []
        }

        /// The cases a `case` declares: `linear, radial` in `case linear, radial`, `unknown`
        /// in `case unknown(String)`; nothing for a `case let` or `case .x:` pattern.
        private static func caseNames(_ chars: [Character], from index: Int) -> [String] {
            var end = index
            while end < chars.count, chars[end] != "\n", chars[end] != ":", chars[end] != "=" {
                end += 1
            }
            var names: [String] = []
            for part in String(chars[index ..< end]).split(separator: ",") {
                // `case \`default\``: a keyword made a name.
                let name = Self.trimmed(part).filter { $0 != "`" }.prefix { isIdentifierBody($0) }
                if let first = name.first, isIdentifierHead(first), name != "let", name != "var" {
                    names.append(String(name))
                }
            }
            return names
        }

        /// The parameters of the closure whose `in` starts at `index`: `a, b` in
        /// `{ a, b in`, `(a, b)` in `{ (a, b) in`.
        private static func closureParameters(_ chars: [Character], before index: Int) -> [String] {
            var start = index
            while start > 0, chars[start - 1] != "{", chars[start - 1] != "\n" {
                start -= 1
            }
            guard start > 0, chars[start - 1] == "{" else { return [] }
            let list = String(chars[start ..< index]).filter { $0 != "(" && $0 != ")" }
            return list.split(separator: ",").map(Self.trimmed)
                .filter { name in name.allSatisfy(isIdentifierBody) && !name.isEmpty }
        }

        private static func trimmed(_ text: Substring) -> String {
            String(text.drop { $0 == " " || $0 == "\t" }.reversed().drop { $0 == " " || $0 == "\t" }.reversed())
        }
    }
}
