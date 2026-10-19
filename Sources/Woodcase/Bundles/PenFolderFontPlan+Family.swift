//
//  PenFolderFontPlan+Family.swift
//  Woodcase
//

import Foundation

public extension PenFolderFontPlan {
    /// One family a document draws, as one row of a Pen Folder export's font list.
    struct Family: Friendly, Identifiable {
        /// The family as the document's text writes it.
        public var name: String

        /// The faces the document draws it in, sorted.
        public var faces: [PenFontFace]

        /// Where its fonts come from.
        public var source: Source

        /// The files that would ship: for ``Source/declared`` the document's local
        /// declared files that exist; for ``Source/installed`` the file Core Text draws
        /// each face in; none otherwise. Sorted by file name, each once.
        public var files: [FontFile]

        /// What Google Fonts said about the name: only asked of a family neither
        /// declared nor shipped with the system.
        public var googleFonts: GoogleFontsAnswer

        /// A row.
        ///
        /// - Parameters:
        ///   - name: The family as the document writes it.
        ///   - faces: The faces drawn in it.
        ///   - source: Where its fonts come from.
        ///   - files: The files that would ship.
        ///   - googleFonts: What Google Fonts said about the name.
        public init(
            name: String,
            faces: [PenFontFace],
            source: Source,
            files: [FontFile],
            googleFonts: GoogleFontsAnswer = .notAsked
        ) {
            self.name = name
            self.faces = faces
            self.source = source
            self.files = files
            self.googleFonts = googleFonts
        }

        /// The family name: one row per family.
        public var id: String {
            name
        }

        /// Whether the export can carry it: a declared or installed family with a file.
        public var isBundleable: Bool {
            (source == .declared || source == .installed) && !files.isEmpty
        }

        /// Whether its checkbox starts checked: every bundleable row does.
        public var startsChecked: Bool {
            isBundleable
        }

        /// Why the row is disabled, or what a checked row warns about; `nil` for a
        /// bundleable family whose every file allows installable or editable embedding.
        public var reason: Reason? {
            switch source {
            case .system: return .systemFont
            case .googleFonts: return .googleFonts
            case .missing: return googleFonts == .unreachable ? .googleFontsUnreachable : .notFound
            case .declared, .installed:
                guard isBundleable else { return source == .declared ? .declaredRemotely : .notFound }
                if files.contains(where: { $0.embedding == nil }) { return .unreadableEmbedding }
                switch permission {
                case .restricted?: return .restrictedEmbedding
                case .previewAndPrint?: return .previewAndPrintEmbedding
                default: return nil
                }
            }
        }

        /// The most restrictive embedding permission among its files that have one, or
        /// `nil` when none does.
        public var permission: PenFontEmbedding.Permission? {
            let order: [PenFontEmbedding.Permission] = [.restricted, .previewAndPrint, .editable, .installable]
            let permissions = Set(files.compactMap(\.embedding?.permission))
            return order.first(where: permissions.contains)
        }
    }

    /// What Google Fonts said when asked whether it has a family.
    enum GoogleFontsAnswer: String, Friendly, CaseIterable {
        /// The family was declared or the system's; nobody asked.
        case notAsked
        /// Google Fonts has it.
        case listed
        /// Google Fonts answered that it has no such family.
        case notListed
        /// Google Fonts could not be reached, so nobody knows.
        case unreachable
    }
}
