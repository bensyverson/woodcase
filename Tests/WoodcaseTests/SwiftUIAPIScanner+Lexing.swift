//
//  SwiftUIAPIScanner+Lexing.swift
//  WoodcaseTests
//

extension SwiftUIAPIScanner {
    /// `source` with its comments removed, every string literal emptied (`""`), and its
    /// `import` and `#if` lines dropped: only the code that calls something.
    static func code(_ source: String) -> String {
        var out = ""
        var chars = Array(source)[...]
        while let c = chars.first {
            if chars.starts(with: "//") {
                chars = chars.drop { $0 != "\n" }
            } else if chars.starts(with: "/*") {
                chars = chars.dropFirst(2)
                while !chars.isEmpty, !chars.starts(with: "*/") {
                    chars = chars.dropFirst()
                }
                chars = chars.dropFirst(2)
            } else if c == "\"" {
                out += "\"\""
                chars = skipLiteral(chars)
            } else {
                out.append(c)
                chars = chars.dropFirst()
            }
        }
        return out.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let trimmed = line.drop { $0 == " " || $0 == "\t" }
            return !trimmed.hasPrefix("import ") && !trimmed.hasPrefix("#if") && !trimmed.hasPrefix("#else")
                && !trimmed.hasPrefix("#elseif") && !trimmed.hasPrefix("#endif")
        }.joined(separator: "\n")
    }

    /// The contents of `source`'s single-line string literals, each interpolation removed
    /// and its escapes resolved: the code fragments a generator writes.
    static func literals(in source: String) -> [String] {
        var found: [String] = []
        var chars = Array(withoutComments(source))[...]
        while let c = chars.first {
            chars = chars.dropFirst()
            guard c == "\"" else { continue }
            if chars.starts(with: "\"\"") { // a multi-line literal: prose, not code
                chars = chars.dropFirst(2)
                while !chars.isEmpty, !chars.starts(with: "\"\"\"") {
                    chars = chars.dropFirst()
                }
                chars = chars.dropFirst(3)
                continue
            }
            var content = ""
            while let d = chars.first, d != "\"", d != "\n" {
                chars = chars.dropFirst()
                guard d == "\\", let escaped = chars.first else {
                    content.append(d)
                    continue
                }
                chars = chars.dropFirst()
                if escaped == "(" {
                    chars = skipBalanced(chars, depth: 1)
                } else {
                    content.append(escaped == "n" ? "\n" : escaped)
                }
            }
            chars = chars.dropFirst()
            found.append(content)
        }
        return found
    }

    /// `source` with comments removed and literals kept, for ``literals(in:)``.
    static func withoutComments(_ source: String) -> String {
        var out = ""
        var chars = Array(source)[...]
        while let c = chars.first {
            if chars.starts(with: "//") {
                chars = chars.drop { $0 != "\n" }
            } else if c == "\"" {
                let rest = skipLiteral(chars)
                out += String(chars.prefix(chars.count - rest.count))
                chars = rest
            } else {
                out.append(c)
                chars = chars.dropFirst()
            }
        }
        return out
    }

    /// `chars` after the string literal that opens at its start.
    static func skipLiteral(_ chars: ArraySlice<Character>) -> ArraySlice<Character> {
        if chars.starts(with: "\"\"\"") {
            var rest = chars.dropFirst(3)
            while !rest.isEmpty, !rest.starts(with: "\"\"\"") {
                rest = rest.dropFirst(rest.first == "\\" ? 2 : 1)
            }
            return rest.dropFirst(3)
        }
        var rest = chars.dropFirst()
        while let c = rest.first, c != "\"", c != "\n" {
            if c == "\\", rest.dropFirst().first == "(" {
                rest = skipBalanced(rest.dropFirst(2), depth: 1)
            } else {
                rest = rest.dropFirst(c == "\\" ? 2 : 1)
            }
        }
        return rest.dropFirst()
    }

    /// `chars` after the parenthesis that closes `depth` open ones, nested literals skipped.
    static func skipBalanced(_ chars: ArraySlice<Character>, depth: Int) -> ArraySlice<Character> {
        var rest = chars
        var depth = depth
        while let c = rest.first, depth > 0 {
            if c == "\"" {
                rest = skipLiteral(rest)
                continue
            }
            if c == "(" { depth += 1 }
            if c == ")" { depth -= 1 }
            rest = rest.dropFirst()
        }
        return rest
    }
}
