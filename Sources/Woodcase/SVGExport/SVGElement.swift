//
//  SVGElement.swift
//  Woodcase
//

import Foundation

/// One element of an SVG document: a name, its attributes in the order they were set, and
/// either child elements or text.
///
/// The SVG writer builds a tree of these and serializes it once, so escaping lives in one
/// place (``xml``) and no caller concatenates markup by hand.
struct SVGElement: Friendly {
    /// The element's name, `path` or `linearGradient`.
    var name: String
    /// The attributes, in writing order. Setting one already present replaces it in place.
    private(set) var attributes: [Attribute] = []
    /// The child elements.
    var children: [SVGElement] = []
    /// The element's text, for a `tspan`; written escaped, after any children.
    var text: String?

    /// One attribute: a name and its unescaped value.
    struct Attribute: Friendly {
        /// The attribute's name.
        let name: String
        /// Its value, unescaped.
        var value: String
    }

    /// Creates an element.
    ///
    /// - Parameters:
    ///   - name: The element's name.
    ///   - attributes: Its attributes, in order; a `nil` value is left out.
    ///   - children: Its child elements.
    init(_ name: String, _ attributes: KeyValuePairs<String, String?> = [:], children: [SVGElement] = []) {
        self.name = name
        self.children = children
        for (key, value) in attributes {
            if let value { self[key] = value }
        }
    }

    /// The value of the attribute `key`, or `nil`; setting `nil` removes it.
    subscript(key: String) -> String? {
        get { attributes.first { $0.name == key }?.value }
        set {
            if let index = attributes.firstIndex(where: { $0.name == key }) {
                if let newValue { attributes[index].value = newValue } else { attributes.remove(at: index) }
            } else if let newValue {
                attributes.append(Attribute(name: key, value: newValue))
            }
        }
    }

    /// The element as XML: self-closing when it has neither children nor text, no
    /// whitespace added between elements, so a `tspan`'s spaces survive as written.
    var xml: String {
        var out = ""
        write(into: &out)
        return out
    }

    /// Appends the element's XML to `out`.
    private func write(into out: inout String) {
        out += "<" + name
        for attribute in attributes {
            out += " " + attribute.name + "=\"" + Self.escape(attribute.value, quotes: true) + "\""
        }
        guard !children.isEmpty || text != nil else {
            out += "/>"
            return
        }
        out += ">"
        for child in children {
            child.write(into: &out)
        }
        if let text {
            out += Self.escape(text, quotes: false)
        }
        out += "</" + name + ">"
    }

    /// `text` with XML's markup characters escaped, and quotes too inside an attribute.
    static func escape(_ text: String, quotes: Bool) -> String {
        var out = ""
        out.reserveCapacity(text.utf8.count)
        for character in text {
            switch character {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            case "\"" where quotes: out += "&quot;"
            default: out.append(character)
            }
        }
        return out
    }
}
