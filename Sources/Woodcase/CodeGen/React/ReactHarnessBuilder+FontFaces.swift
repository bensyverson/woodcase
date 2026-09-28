//
//  ReactHarnessBuilder+FontFaces.swift
//  Woodcase
//

import CoreText
import Foundation

extension ReactHarnessBuilder {
    /// One `@font-face` rule: the family, weights and style a page asks for, and the file
    /// that answers.
    ///
    /// Every field is read from the font itself, never from its file name: a variable
    /// font's file is named for its axes (`Inter[opsz,wght].ttf`), and a face named after
    /// it is one no page ever asks for.
    struct FontFace: Friendly {
        /// The weights a face answers for.
        enum Weight: Friendly {
            /// A static cut: its OS/2 weight class.
            case fixed(Int)
            /// A variable font: its `wght` axis, from minimum to maximum.
            case range(ClosedRange<Int>)

            /// The value of the rule's `font-weight` descriptor.
            var css: String {
                switch self {
                case let .fixed(weight): "\(weight)"
                case let .range(range): "\(range.lowerBound) \(range.upperBound)"
                }
            }
        }

        /// The styles a face answers for.
        enum Style: String, Friendly {
            /// Upright.
            case normal
            /// Italic.
            case italic
        }

        /// The family the font's name table declares.
        let family: String
        /// The weights the file can draw.
        let weight: Weight
        /// Whether the file is upright or italic.
        let style: Style
        /// The file's name.
        let fileName: String

        /// The OpenType tag of the weight axis, `'wght'`.
        private static let weightAxisTag: Int = 0x7767_6874

        /// Where the OS/2 table keeps `usWeightClass`: a big-endian `UInt16` at byte 4.
        private static let weightClassOffset: Int = 4

        /// The weight CSS assumes of a face that states none.
        private static let regularWeight: Int = 400

        /// Reads the face of the font file at `url`, or `nil` when it holds no font.
        ///
        /// A variable font lists one descriptor per named instance; every one shares the
        /// file's family and axes, so the first speaks for the file.
        ///
        /// - Parameter url: a `.ttf` or `.otf` file on disk.
        init?(fontFile url: URL) {
            guard let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor],
                  let descriptor = descriptors.first,
                  let family = CTFontDescriptorCopyAttribute(descriptor, kCTFontFamilyNameAttribute) as? String
            else { return nil }
            let font = CTFontCreateWithFontDescriptor(descriptor, 0, nil)
            self.family = family
            weight = Self.weightAxis(of: font).map(Weight.range) ?? .fixed(Self.weightClass(of: font))
            style = CTFontGetSymbolicTraits(font).contains(.traitItalic) ? .italic : .normal
            fileName = url.lastPathComponent
        }

        /// The rule, its `src` the file at `path` under `relativePath` from the page.
        func css(relativePath: String, path: String) -> String {
            let format = fileName.lowercased().hasSuffix(".otf") ? "opentype" : "truetype"
            let quoted = family.replacingOccurrences(of: "'", with: "\\'")
            return """
            @font-face {
              font-family: '\(quoted)';
              font-weight: \(weight.css);
              font-style: \(style.rawValue);
              src: url('\(relativePath)/\(path)') format('\(format)');
            }\n
            """
        }

        /// The `wght` axis's range, or `nil` for a font without one.
        private static func weightAxis(of font: CTFont) -> ClosedRange<Int>? {
            let axes = CTFontCopyVariationAxes(font) as? [[String: Any]] ?? []
            for axis in axes {
                guard let tag = axis[kCTFontVariationAxisIdentifierKey as String] as? Int, tag == weightAxisTag,
                      let minimum = axis[kCTFontVariationAxisMinimumValueKey as String] as? Double,
                      let maximum = axis[kCTFontVariationAxisMaximumValueKey as String] as? Double,
                      minimum <= maximum
                else { continue }
                return Int(minimum.rounded()) ... Int(maximum.rounded())
            }
            return nil
        }

        /// The OS/2 table's `usWeightClass`, or 400 for a font without one.
        private static func weightClass(of font: CTFont) -> Int {
            let tag = CTFontTableTag(kCTFontTableOS2)
            guard let table = CTFontCopyTable(font, tag, []) as Data?, table.count >= weightClassOffset + 2 else {
                return regularWeight
            }
            let bytes = [UInt8](table)
            let weight = Int(bytes[weightClassOffset]) << 8 | Int(bytes[weightClassOffset + 1])
            return weight > 0 ? weight : regularWeight
        }
    }

    /// The font-file extensions a harness page loads.
    private static let fontFileExtensions: Set<String> = ["ttf", "otf"]

    /// Builds one `@font-face` rule per font file in `fontDir` and in its folders, each
    /// referenced at its path under `relativePath` from the page and named by the family
    /// its name table declares: `GoogleFonts/Spectral-Bold.ttf` is Spectral at 700.
    static func buildFontFaceCSS(relativePath: String, fontDir: URL) -> String {
        let root = fontDir.standardizedFileURL.resolvingSymlinksInPath().path + "/"
        guard let entries = FileManager.default.enumerator(at: fontDir, includingPropertiesForKeys: nil) else {
            return ""
        }
        return entries
            .compactMap { $0 as? URL }
            .filter { fontFileExtensions.contains($0.pathExtension.lowercased()) }
            .map { url -> (path: String, url: URL) in
                let full = url.standardizedFileURL.resolvingSymlinksInPath().path
                return (full.hasPrefix(root) ? String(full.dropFirst(root.count)) : url.lastPathComponent, url)
            }
            .sorted { $0.path < $1.path }
            .compactMap { file in FontFace(fontFile: file.url).map { $0.css(relativePath: relativePath, path: file.path) } }
            .joined()
    }
}
