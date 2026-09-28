//
//  SwiftUIAPIScannerTests.swift
//  WoodcaseTests
//

import Testing

/// How ``SwiftUIAPIScanner`` reads a piece of emitted Swift: which names it takes for SDK
/// uses, with what argument labels, and which it leaves to the code's own declarations.
struct SwiftUIAPIScannerTests {
    private func uses(_ source: String) -> [String] {
        SwiftUIAPIScanner.uses(in: SwiftUIAPIScanner.code(source)).map(\.description)
    }

    @Test("A modifier chain is member calls with their labels")
    func modifierChain() {
        #expect(uses("Rectangle().fill(Color.black).frame(width: 2, height: 3)") == [
            "Rectangle()", ".fill(_:)", "Color", ".black", ".frame(width:height:)",
        ])
    }

    @Test("A trailing closure counts as one argument after the labelled ones")
    func trailingClosure() {
        #expect(uses("ZStack(alignment: .topLeading) { Text(title) }") == [
            "ZStack(alignment:{})", ".topLeading", "Text(_:)",
        ])
        #expect(uses("content.overlay { paint() }") == [".overlay({})", "paint()"])
    }

    @Test("A type in a declaration's type position is a type, not a call")
    func typePositionIsNotACall() {
        #expect(uses("struct A: View {\n var body: some View {\n EmptyView()\n }\n}") == [
            "View", "View", "EmptyView()",
        ])
        #expect(uses("func f() -> Path {\n Path()\n}") == ["Path", "Path()"])
    }

    @Test("Comments, string contents, imports and compiler directives are not code")
    func nonCodeIsSkipped() {
        let source = """
        import SwiftUI
        #if canImport(UIKit)
        // Color.red is only a comment
        let s = "Color.blue(label:)"
        #endif
        if #available(iOS 26, macOS 26, *) { EmptyView() }
        """
        #expect(uses(source) == ["EmptyView()"])
    }

    @Test("Key paths, attributes and macros are read, and numbers are not members")
    func sigils() {
        #expect(uses("@Environment(\\.isEnabled) private var isEnabled") == ["@Environment(_:)", "\\.isEnabled"])
        #expect(uses("#Preview(\"A\") { EmptyView() }") == ["#Preview(_:{})", "EmptyView()"])
        #expect(uses("let x = 0.5 * y.width") == [".width"])
    }

    @Test("A brace ending an if, guard, for or while line opens its body, not a trailing closure")
    func controlLines() {
        #expect(uses("if let image = renderer.cgImage {\n}") == [".cgImage"])
        #expect(uses("for (a, b) in zip(xs, ys) {\n}") == ["zip(_:_:)"])
        #expect(uses("} else if list.contains(x) {\n}") == [".contains(_:)"])
        #expect(uses("switch mode {\ncase .dark: 1\n}") == [".dark"])
        #expect(uses("guard let flag = args.firstIndex(of: y) else {\n}") == [".firstIndex(of:)"])
    }

    @Test("A qualified member records the name it is reached through")
    func receivers() {
        let found = SwiftUIAPIScanner.uses(in: SwiftUIAPIScanner.code("theme.meshCool; a.b().c"))
        #expect(found.map(\.receiver) == ["theme", "a", nil])
    }

    @Test("Core Text constants are uses even as dictionary keys; plain locals are not")
    func constants() {
        #expect(uses("let a = [kCTFontFamilyNameAttribute: family]") == ["kCTFontFamilyNameAttribute"])
    }

    @Test("Declarations collect functions, values, statics, types and initializer labels")
    func declarations() {
        let code = SwiftUIAPIScanner.code("""
        struct PenBox<S: Shape>: View {
            enum Kind { case linear, radial }
            static let margin: CGFloat = 1
            var shape: S
            init(_ shape: S, color c: Color) {}
            func penFit(from size: CGSize) -> Path { Path() }
            var body: some View { ForEach(items) { item, index in EmptyView() } }
        }
        """)
        let declared = SwiftUIAPIScanner.Declarations(code)
        #expect(declared.types.isSuperset(of: ["PenBox", "S", "Kind"]))
        #expect(declared.functions == ["penFit"])
        #expect(declared.statics.isSuperset(of: ["linear", "radial", "margin"]))
        #expect(declared.values.isSuperset(of: ["shape", "color", "c", "size", "item", "index", "body"]))
        #expect(declared.initializers == [["_", "color"]])
    }

    @Test("Tuple labels are values, backticked and keyword-named cases are cases, and a self.init is the code's own")
    func declarationEdges() {
        let code = SwiftUIAPIScanner.code("""
        func v() -> (p: SIMD2<Float>, l: Float) { }
        enum Density { case `default`, open }
        init(title: String) { self.init(title: title, content: {}) }
        init(title: String, content: () -> Void) {}
        """)
        let declared = SwiftUIAPIScanner.Declarations(code)
        #expect(declared.values.isSuperset(of: ["p", "l"]))
        #expect(declared.statics.isSuperset(of: ["default", "open"]))
        let selfInit = SwiftUIAPIScanner.uses(in: code).filter { $0.name == "init" }
        #expect(selfInit.count == 1 && selfInit.allSatisfy(declared.declares))
    }

    @Test("A string literal yields its code fragment, interpolations and escapes removed")
    func literals() {
        let source = #"let a = ".frame(width: \(w), alignment: \"x\")"; let b = "no code here""#
        #expect(SwiftUIAPIScanner.literals(in: source) == [".frame(width: , alignment: \"x\")", "no code here"])
    }
}
