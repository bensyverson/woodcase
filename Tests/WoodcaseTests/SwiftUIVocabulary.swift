//
//  SwiftUIVocabulary.swift
//  WoodcaseTests
//

import Woodcase

/// The SwiftUI emitter's vocabulary, as `Fixtures/swiftui-vocabulary.txt` lists it: one
/// dotted symbol-graph path per line — the input `scripts/swiftui-api audit` checks against
/// the SDK — and whether a use the scanner found is one of them.
///
/// A path covers a use by name and labels, whatever the owner: the scanner cannot tell
/// `Shape.fill` from `GraphicsContext.fill`, so a use is covered when some listed path has
/// its name and a label list the call fits.
struct SwiftUIVocabulary: Friendly {
    /// One listed path and its annotations.
    struct Entry: Friendly {
        /// The dotted path: `View.frame(width:height:alignment:)`, `Alignment.topLeading`.
        var path: String

        /// The `#available` gate an `@available ios=26,macos=26` annotation names, as written.
        var gate: String?

        /// The platforms an `@only macos` annotation names, as written.
        var only: String?

        /// The path's components before its last: `["View"]`, `["MeshGradient", "BezierPoint"]`.
        var owners: [String]

        /// The last component's name: `frame`, `topLeading`, `init`, `CTFontGetAscent`.
        var name: String

        /// The last component's labels, `_` for an unlabeled parameter, or `nil` for a
        /// path that is not a function: `["width", "height", "alignment"]`.
        var labels: [String]?
    }

    /// A line the list cannot hold.
    struct ParseError: Error, Friendly, CustomStringConvertible {
        /// The line, counted from 1.
        var line: Int

        /// What is wrong with it.
        var reason: String

        var description: String {
            "swiftui-vocabulary.txt:\(line): \(reason)"
        }
    }

    /// The listed paths, in file order.
    var entries: [Entry] = []

    /// An empty list.
    init() {}

    /// The list in `text`: a path per line, `#` comments and blank lines ignored.
    init(_ text: String) throws {
        for (number, raw) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let words = raw.prefix { $0 != "#" }.split(whereSeparator: \.isWhitespace).map(String.init)
            guard let path = words.first else { continue }
            var entry = Self.entry(path)
            var rest = words.dropFirst()
            while let annotation = rest.popFirst() {
                guard let value = rest.popFirst() else {
                    throw ParseError(line: number + 1, reason: "\(annotation) needs a value")
                }
                switch annotation {
                case "@available": entry.gate = value
                case "@only": entry.only = value
                default: throw ParseError(line: number + 1, reason: "unknown annotation \(annotation)")
                }
            }
            entries.append(entry)
        }
    }

    /// The list of `paths`, without annotations.
    init(paths: [String]) {
        entries = paths.map(Self.entry)
    }

    /// Whether some listed path covers `use`. With `byNameOnly`, a call's labels are not
    /// compared: for a fragment whose arguments were interpolated away.
    func covers(_ use: SwiftUIAPIUse, byNameOnly: Bool = false) -> Bool {
        let fits: (Entry) -> Bool = { entry in
            guard let labels = use.labels, !byNameOnly else { return true }
            guard let listed = entry.labels else { return false }
            return Self.fits(labels, trailing: use.trailingClosures, into: listed)
        }
        if use.access == .macro {
            return entries.contains { $0.owners.isEmpty && $0.name == use.name && fits($0) }
        }
        if use.isCapitalized {
            guard use.labels != nil else {
                // A type, named anywhere in a path: `Configuration` by `ButtonStyle.Configuration`.
                return entries.contains { $0.owners.contains(use.name) || $0.name == use.name }
            }
            // A call: an initializer of the type, or a C function or macro of that name.
            return entries.contains { entry in
                (entry.name == "init" && entry.owners.last == use.name && fits(entry))
                    || (entry.owners.isEmpty && entry.name == use.name && fits(entry))
            }
        }
        if use.labels == nil {
            return entries.contains { $0.name == use.name }
        }
        return entries.contains { $0.name == use.name && fits($0) }
    }

    /// Whether a call with `labels` and `trailing` trailing closures can call a function
    /// whose parameters are `listed`: its labels an in-order subset of the listed ones (the
    /// rest defaulted), and a listed parameter after them for each trailing closure.
    static func fits(_ labels: [String], trailing: Int, into listed: [String]) -> Bool {
        var next = listed.startIndex
        for label in labels {
            guard let match = listed[next...].firstIndex(of: label) else { return false }
            next = match + 1
        }
        return listed.count - next >= trailing
    }

    /// A path split into its owners, name and labels.
    private static func entry(_ path: String) -> Entry {
        var components: [String] = []
        var current = ""
        var depth = 0
        for c in path {
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            if c == ".", depth == 0 {
                components.append(current)
                current = ""
            } else {
                current.append(c)
            }
        }
        let last = current
        guard let open = last.firstIndex(of: "(") else {
            return Entry(path: path, owners: components, name: last)
        }
        let labels = last[last.index(after: open)...].dropLast().split(separator: ":").map(String.init)
        return Entry(path: path, owners: components, name: String(last[..<open]), labels: labels)
    }
}
