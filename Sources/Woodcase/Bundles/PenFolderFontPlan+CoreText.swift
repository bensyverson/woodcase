//
//  PenFolderFontPlan+CoreText.swift
//  Woodcase
//

#if canImport(CoreText)
    import CoreText
#endif
import Foundation

extension PenFolderFontPlan {
    /// What a font file's name table says: its family and its license.
    struct FontFileNames: Friendly {
        /// The family name (name ID 1, or 16 where the font has one).
        var family: String

        /// The license it carries, or `nil`.
        var license: License?
    }
}

#if canImport(CoreText)
    extension PenFolderFontPlan.FontFileNames {
        /// The names of a file's first font, or `nil` when Core Text reads no font there.
        init?(fileAt url: URL) {
            guard let names = FontRegistryGate.withAccess({ () -> Self? in
                let descriptors = (CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor]) ?? []
                guard let first = descriptors.first else { return nil }
                return Self(font: CTFontCreateWithFontDescriptor(first, 12, nil))
            }) else { return nil }
            self = names
        }

        /// The names of a font.
        init(font: CTFont) {
            let name = { (key: CFString) -> String? in
                guard let value = CTFontCopyName(font, key) as String? else { return nil }
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty ? nil : trimmed
            }
            let description = name(kCTFontLicenseNameKey)
            let url = name(kCTFontLicenseURLNameKey).flatMap(URL.init(string:))
            self.init(
                family: CTFontCopyFamilyName(font) as String,
                license: description == nil && url == nil
                    ? nil
                    : PenFolderFontPlan.License(description: description, url: url)
            )
        }
    }

    extension PenFolderFontPlan {
        /// Whether Apple made the font Core Text draws `face` in (``PenFontMaker/isApple``),
        /// when it is a font of the family — wherever its file is.
        ///
        /// The face resolves as ``installedFile(_:)`` resolves it, so this asks of the
        /// file that would ship; a fallback to another family is not the family's.
        ///
        /// - Parameter face: The face.
        /// - Returns: Whether Apple made it.
        static func isAppleMade(_ face: PenFontFace) -> Bool {
            let font = PenTextMeasurer.resolveFont(
                family: face.family, size: 12, weight: String(face.weight), style: face.style.rawValue
            )
            return FontRegistryGate.withAccess {
                (CTFontCopyFamilyName(font) as String).lowercased() == face.family.lowercased()
                    && PenFontMaker(font: font)?.isApple == true
            }
        }

        /// The file Core Text draws `face` in, when it is a font of the family outside the
        /// system's folders — the file a Pen Folder would ship for an installed family.
        ///
        /// The face resolves the way the renderer resolves it
        /// (``PenTextMeasurer/resolveFont(family:size:weight:style:)``), so the file is
        /// the one the canvas draws in; a fallback to another family is no file.
        ///
        /// - Parameter face: The face.
        /// - Returns: The file, or `nil`.
        static func installedFile(_ face: PenFontFace) -> FontFile? {
            let font = PenTextMeasurer.resolveFont(
                family: face.family, size: 12, weight: String(face.weight), style: face.style.rawValue
            )
            return FontRegistryGate.withAccess {
                let names = FontFileNames(font: font)
                guard names.family.lowercased() == face.family.lowercased(),
                      let url = CTFontCopyAttribute(font, kCTFontURLAttribute) as? URL,
                      !url.path.hasPrefix("/System/"), !url.path.hasPrefix("/Library/Apple/")
                else { return nil }
                let weights = PenTextMeasurer.drawnWeights(of: font)
                let os2 = CTFontCopyTable(font, CTFontTableTag(kCTFontTableOS2), []) as Data?
                return FontFile(
                    url: url,
                    familyName: names.family,
                    style: CTFontGetSymbolicTraits(font).contains(.traitItalic) ? .italic : .normal,
                    weight: weights.lowerBound == weights.upperBound
                        ? .single(Double(weights.lowerBound))
                        : .range(from: Double(weights.lowerBound), to: Double(weights.upperBound)),
                    embedding: os2.flatMap(PenFontEmbedding.init(os2Table:)),
                    license: names.license
                )
            }
        }
    }
#else
    extension PenFolderFontPlan.FontFileNames {
        /// No font reader without Core Text.
        init?(fileAt _: URL) {
            nil
        }
    }

    extension PenFolderFontPlan {
        /// No installed fonts, so none Apple made, without Core Text.
        static func isAppleMade(_: PenFontFace) -> Bool {
            false
        }

        /// No installed fonts without Core Text.
        static func installedFile(_: PenFontFace) -> FontFile? {
            nil
        }
    }
#endif
