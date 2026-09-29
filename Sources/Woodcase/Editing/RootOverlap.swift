//
//  RootOverlap.swift
//  Woodcase
//

import Foundation

/// Two root nodes whose settled rects sit on top of each other.
///
/// A document's roots are artboards on an infinite canvas, and **artboards do not
/// overlap**: one drawn over another hides it in every view that shows the whole
/// canvas, and nothing in the format says which of the two is on top. So a root added
/// or copied without coordinates is placed clear of every existing root by
/// ``margin``, and a root written *with* coordinates that land
/// on another is allowed — the author may be mid-edit — but said out loud: the write
/// warns, and ``LintCheck/artboardOverlap`` reports the pair until it is resolved.
///
/// The pairing is the same walk on both sides. ``overlaps(among:)`` is the whole test,
/// and its two callers differ only in where they get their rects: a write measures the
/// roots alone with ``roots(in:textMeasurer:)``, and `DocumentLinter` reads the settled
/// rects of the tree read it is already doing. The two agree exactly — see
/// ``EditableDocument/rootRects(textMeasurer:)``.
///
/// ```swift
/// for overlap in RootOverlap.overlaps(in: document) {
///     print(overlap.message(file: "design.pen"))
/// }
/// // Checkout (Chk01) 150,40 200×100 overlaps Home (Home1) 0,0 200×100. …
/// ```
public struct RootOverlap: Friendly {
    /// The empty space artboards keep between them, in points.
    ///
    /// One number, two jobs: it is how far to the right of the existing roots an
    /// auto-placed one lands (`BatchApplier.placedAtRoot(_:in:coordinates:)`), and it
    /// is the clearance ``clearingX`` suggests when two roots have collided. They have
    /// to agree — a remedy that put a root somewhere placement would not is a remedy
    /// that teaches the wrong rule — so there is one constant and both read it.
    ///
    /// 100 points is wide enough to read as deliberate space at any zoom the whole
    /// canvas fits in, and narrow enough that a document of many artboards does not
    /// sprawl.
    public static let margin: Double = 100

    /// One of the two roots: what it is called, what it is, and where it settled.
    public struct Root: Friendly {
        /// Creates a root.
        ///
        /// - Parameters:
        ///   - id: The root node's id.
        ///   - name: Its name, or `nil` for an unnamed node.
        ///   - rect: Its settled rect, in canvas coordinates; kept as its bounds alone
        ///     (``PenRect/bounds``), which is all an overlap is about.
        public init(id: String, name: String?, rect: PenRect) {
            self.id = id
            self.name = name
            self.rect = rect.bounds
        }

        /// The root node's id.
        public let id: String

        /// Its name, or `nil` for an unnamed node.
        public let name: String?

        /// Its settled rect, in canvas coordinates.
        public let rect: PenRect

        /// The root as a reader recognizes it: its name, or its id marker.
        public var label: String {
            name ?? NodeAddress.marker(forID: id)
        }

        /// The root named and measured in one clause: `Home (Home1) 0,0 200×100`.
        public var described: String {
            "\(label) (\(id)) \(rect.readable)"
        }
    }

    /// The two ids, in a fixed order, identifying the pair however either root moves.
    ///
    /// A write warns about the overlaps it *created*, which means comparing the pairs
    /// before an edit with the pairs after it. Rects change on both sides of such an
    /// edit, so the comparison has to be on identity alone.
    public struct Pair: Friendly {
        /// Creates a pair from two ids, in either order.
        ///
        /// - Parameters:
        ///   - one: One root's id.
        ///   - other: The other root's id.
        public init(_ one: String, _ other: String) {
            first = min(one, other)
            second = max(one, other)
        }

        /// The lower of the two ids.
        public let first: String

        /// The higher of the two ids.
        public let second: String
    }

    /// Creates an overlap.
    ///
    /// - Parameters:
    ///   - earlier: The root that comes first in ``EditableDocument/rootOrder``.
    ///   - later: The root that comes after it — the one a remedy moves.
    public init(earlier: Root, later: Root) {
        self.earlier = earlier
        self.later = later
    }

    /// The root that comes first in the document's root order.
    public let earlier: Root

    /// The root that comes after it, and the one a remedy moves.
    ///
    /// Moving the later of the two is the smaller surprise: it is the one a caller most
    /// likely just added or just wrote coordinates for.
    public let later: Root

    /// The two roots' ids, order-independent.
    public var pair: Pair {
        Pair(earlier.id, later.id)
    }

    /// The first `x` that would put ``later`` clear of ``earlier`` by the placement
    /// margin — the value the remedy suggests.
    public var clearingX: Double {
        earlier.rect.x + earlier.rect.width + RootOverlap.margin
    }

    /// What is wrong and what to do about it, as a lint finding's message.
    ///
    /// - Parameter file: The .pen file to name in the suggested command. A caller with
    ///   no file at hand — the linter, which is handed a document — passes the literal
    ///   `"<file>"`, because a command with a wrong path in it teaches worse than a
    ///   command with a blank in it.
    /// - Returns: One sentence naming both roots and their rects, then the command that
    ///   separates them.
    public func message(file: String) -> String {
        "\(later.rect.readable) overlaps \(earlier.described). Artboards do not overlap: run "
            + "`woodcase set \(file) \(later.id) common.x=\(PenRect.number(clearingX))` to put it "
            + "clear by \(PenRect.number(RootOverlap.margin))pt."
    }

    // MARK: - Finding the overlaps

    /// Every pair of roots that intersect, in document order.
    ///
    /// Comparisons carry ``TreeRow/clipTolerance`` of slack, for the same reason the
    /// clip flag does: two artboards laid edge to edge settle on a shared coordinate
    /// give or take a few parts in 10¹³, and that is not an overlap. Sharing an edge
    /// exactly is not one either.
    ///
    /// - Parameter roots: The roots, in ``EditableDocument/rootOrder``.
    /// - Returns: One overlap per intersecting pair, ordered by the *later* root so the
    ///   findings read in document order, and by the earlier root within that.
    public static func overlaps(among roots: [Root]) -> [RootOverlap] {
        var found: [RootOverlap] = []
        for (index, later) in roots.enumerated() {
            for earlier in roots[roots.startIndex ..< index] where intersect(earlier.rect, later.rect) {
                found.append(RootOverlap(earlier: earlier, later: later))
            }
        }
        return found
    }

    /// Every pair of the document's roots that intersect, in document order.
    ///
    /// - Parameter document: The document to measure. Its layout is computed, so the
    ///   answer is where the roots settle rather than what they declare.
    /// - Returns: One overlap per intersecting pair.
    public static func overlaps(in document: EditableDocument) -> [RootOverlap] {
        overlaps(among: roots(in: document))
    }

    /// The document's roots, named and settled, **component definitions and instances
    /// included**.
    ///
    /// A reusable definition is a root like any other: it sits on the canvas, a design
    /// tool draws it there, and two of them at the same coordinates hide each other. So
    /// is an instance placed at the root, at its component's size. Both are measured
    /// through ``EditableDocument/rootRects(textMeasurer:)``: the rects a full
    /// ``SettledTree`` gives the roots — the ones `DocumentLinter` reads for the same
    /// check — without settling anything but the roots whose size depends on their
    /// content. A write asks this twice, before and after its edit, so this is the one
    /// measurement every writer shares: the verbs, `woodcase js`, and root placement.
    ///
    /// - Parameters:
    ///   - document: The document to measure.
    ///   - textMeasurer: A function that measures text bounding boxes.
    /// - Returns: One ``Root`` per node in ``EditableDocument/rootOrder`` that settles,
    ///   in that order.
    public static func roots(
        in document: EditableDocument,
        textMeasurer: TextMeasurer = PenLayoutEngine.defaultTextMeasurer
    ) -> [Root] {
        let rects = document.rootRects(textMeasurer: textMeasurer)
        return document.rootOrder.compactMap { id in
            guard let rect = rects[id] else { return nil }
            return Root(id: id, name: document.nodes[id]?.common.name, rect: rect)
        }
    }

    /// Whether two rects share more than a tolerance of area.
    private static func intersect(_ one: PenRect, _ other: PenRect) -> Bool {
        let across = min(one.x + one.width, other.x + other.width) - max(one.x, other.x)
        let down = min(one.y + one.height, other.y + other.height) - max(one.y, other.y)
        return across > TreeRow.clipTolerance && down > TreeRow.clipTolerance
    }
}
