import Foundation
import Testing
@testable import Woodcase

@Suite("ReactHarnessBuilder")
struct ReactHarnessBuilderTests {
    private func sampleFiles() -> [GeneratedFile] {
        [
            GeneratedFile(
                path: "theme.css",
                content: ":root { --accent: #C67A52; --bg-page: #FAF8F4; }"
            ),
            GeneratedFile(
                path: "components/MyButton.tsx",
                content: """
                import { cn } from "../lib/cn";
                import { MyIcon } from "./MyIcon";

                interface MyButtonProps {
                  label?: string;
                  className?: string;
                  style?: React.CSSProperties;
                }

                export function MyButton({ label = "Click", className, style }: MyButtonProps) {
                  return (
                    <div className={cn("flex", className)} style={{ backgroundColor: "var(--accent)", ...style }}>
                      <MyIcon />
                      <p>{label}</p>
                    </div>
                  );
                }
                """
            ),
            GeneratedFile(
                path: "components/MyIcon.tsx",
                content: """
                import { cn } from "../lib/cn";

                export function MyIcon({ className, style }: { className?: string; style?: React.CSSProperties }) {
                  return <svg width={24} height={24} />;
                }
                """
            ),
            GeneratedFile(
                path: "components/Unrelated.tsx",
                content: """
                import { cn } from "../lib/cn";

                export function Unrelated() {
                  return <div>Unrelated component</div>;
                }
                """
            ),
            GeneratedFile(
                path: "lib/cn.ts",
                content: """
                export function cn(...classes: (string | undefined | null | false)[]): string {
                  return classes.filter(Boolean).join(" ");
                }
                """
            ),
            GeneratedFile(
                path: "ThemeProvider.tsx",
                content: """
                import { createContext, useContext, useState } from "react";
                export function ThemeProvider({ children }) {
                  return <div>{children}</div>;
                }
                """
            ),
        ]
    }

    @Test("Output references React JS via script src tags")
    func referencesReactJS() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400
        )
        #expect(html.contains("src=\"js/react.production.min.js\""))
        #expect(html.contains("src=\"js/react-dom.production.min.js\""))
        #expect(html.contains("src=\"js/babel.min.js\""))
        #expect(html.contains("src=\"js/tailwindcss.js\""))
    }

    @Test("Output contains inlined theme.css content")
    func containsThemeCSS() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400
        )
        #expect(html.contains("--accent: #C67A52"))
        #expect(html.contains("<style"))
    }

    @Test("Output contains inlined states.css content, so a designer state draws")
    func containsStatesCSS() {
        let files = sampleFiles() + [
            GeneratedFile(path: "states.css", content: ".wc-my-button:disabled {\n  --wc-my-button-transform: rotate(-25deg);\n}\n"),
        ]
        let html = ReactHarnessBuilder.buildHTML(from: files, componentName: "MyButton", viewportWidth: 400)
        #expect(html.contains("--wc-my-button-transform: rotate(-25deg)"))
    }

    @Test("Output contains target component code")
    func containsComponentCode() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400
        )
        #expect(html.contains("function MyButton"))
    }

    @Test("Output contains __READY__ signal")
    func containsReadySignal() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400
        )
        #expect(html.contains("__READY__"))
    }

    @Test("Output sets correct viewport meta tag")
    func containsViewportMeta() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400
        )
        #expect(html.contains("width=400"))
    }

    @Test("Custom JS relative path is used in script src")
    func customJSPath() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400,
            jsRelativePath: "../js"
        )
        #expect(html.contains("src=\"../js/react.production.min.js\""))
    }

    @Test("Font face CSS uses relative path to font files")
    func fontRelativePath() {
        let fontDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fonts")
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400,
            fontRelativePath: "../../Fonts",
            fontDir: fontDir
        )
        #expect(html.contains("url('../../Fonts/"))
        #expect(html.contains("font-family: 'IBM Plex Sans'"))
    }

    @Test("Output includes dependency of target component")
    func includesDependency() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400
        )
        // MyButton imports MyIcon, so MyIcon should be included
        #expect(html.contains("function MyIcon"))
    }

    @Test("Output excludes unrelated components")
    func excludesUnrelatedComponents() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400
        )
        // Unrelated is not imported by MyButton or MyIcon
        #expect(!html.contains("function Unrelated"))
        // ThemeProvider is also not imported by MyButton
        #expect(!html.contains("function ThemeProvider"))
    }

    @Test("Page file resolves component dependencies via imports")
    func pageResolvesComponentDeps() {
        let files: [GeneratedFile] = [
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(
                path: "pages/Dashboard.tsx",
                content: """
                import { Card } from "../components/Card";
                import { cn } from "../lib/cn";

                export function Dashboard() {
                  return <div><Card /><Card /></div>;
                }
                """
            ),
            GeneratedFile(
                path: "components/Card.tsx",
                content: """
                import { cn } from "../lib/cn";

                export function Card({ className, style }: { className?: string; style?: React.CSSProperties }) {
                  return <div className={cn("flex", className)} style={style}>Card</div>;
                }
                """
            ),
            GeneratedFile(
                path: "components/Sidebar.tsx",
                content: """
                export function Sidebar() { return <div>Sidebar</div>; }
                """
            ),
        ]
        let html = ReactHarnessBuilder.buildHTML(
            from: files,
            componentName: "Dashboard",
            viewportWidth: 400
        )
        #expect(html.contains("function Dashboard"))
        #expect(html.contains("function Card"))
        #expect(!html.contains("function Sidebar"))
    }

    @Test("Components referenced via JSX tags are included as dependencies")
    func jsxTagDependencies() {
        let files: [GeneratedFile] = [
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(
                path: "components/Screen.tsx",
                content: """
                import { cn } from "../lib/cn";

                export function Screen({ className, style }) {
                  return (
                    <div className={cn("flex", className)} style={style}>
                      <Header />
                      <Footer />
                    </div>
                  );
                }
                """
            ),
            GeneratedFile(
                path: "components/Header.tsx",
                content: """
                export function Header() { return <div>Header</div>; }
                """
            ),
            GeneratedFile(
                path: "components/Footer.tsx",
                content: """
                export function Footer() { return <div>Footer</div>; }
                """
            ),
            GeneratedFile(
                path: "components/Sidebar.tsx",
                content: """
                export function Sidebar() { return <div>Sidebar</div>; }
                """
            ),
        ]
        let html = ReactHarnessBuilder.buildHTML(
            from: files,
            componentName: "Screen",
            viewportWidth: 400
        )
        #expect(html.contains("function Header"))
        #expect(html.contains("function Footer"))
        #expect(!html.contains("function Sidebar"))
    }

    @Test("Image paths are rewritten when imageRelativePath is set")
    func imagePathRewrite() {
        let files: [GeneratedFile] = [
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(
                path: "components/Card.tsx",
                content: """
                export function Card() {
                  return <div style={{ backgroundImage: "url('./images/photo.png')" }} />;
                }
                """
            ),
        ]
        let html = ReactHarnessBuilder.buildHTML(
            from: files,
            componentName: "Card",
            viewportWidth: 400,
            imageRelativePath: "../images"
        )
        #expect(html.contains("url('../images/photo.png')"))
        #expect(!html.contains("url('./images/photo.png')"))
    }

    @Test("viewportHeight emits #root height constraint")
    func viewportHeightConstraint() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400,
            viewportHeight: 300
        )
        #expect(html.contains("#root { height: 300px; overflow: hidden; }"))
    }

    @Test("CSS reset includes -webkit-font-smoothing: antialiased")
    func fontSmoothing() {
        let html = ReactHarnessBuilder.buildHTML(
            from: sampleFiles(),
            componentName: "MyButton",
            viewportWidth: 400
        )
        #expect(html.contains("-webkit-font-smoothing: antialiased"))
    }

    @Test("Icon stubs render font glyphs when icon font dir is provided")
    func iconFontStubs() {
        let iconFontDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Woodcase")
            .appendingPathComponent("IconFonts")
            .appendingPathComponent("Fonts")
        let files: [GeneratedFile] = [
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(
                path: "components/Card.tsx",
                content: """
                import { Heart } from "lucide-react";

                export function Card() {
                  return <div><Heart size={14} /></div>;
                }
                """
            ),
        ]
        let html = ReactHarnessBuilder.buildHTML(
            from: files,
            componentName: "Card",
            viewportWidth: 400,
            iconFontRelativePath: "../../Sources/Woodcase/IconFonts/Fonts",
            iconFontDir: iconFontDir
        )
        // Should have @font-face for lucide
        #expect(html.contains("font-family: 'lucide'"))
        #expect(html.contains("lucide.ttf"))
        // The Heart stub draws its lucide codepoint
        #expect(html.contains("const Heart = __iconGlyph__(\"lucide\", { regular: \"\\u{"))
        // Should NOT use empty SVG stub
        #expect(!html.contains("viewBox: \"0 0 24 24\""))
    }

    @Test("Page file with lucide-react icons extracts icon stubs")
    func pageIconExtraction() {
        let iconFontDir = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Sources")
            .appendingPathComponent("Woodcase")
            .appendingPathComponent("IconFonts")
            .appendingPathComponent("Fonts")
        let files: [GeneratedFile] = [
            GeneratedFile(path: "theme.css", content: ":root {}"),
            GeneratedFile(
                path: "components/StatusBar.tsx",
                content: """
                export function StatusBar({ style }: { style?: React.CSSProperties }) {
                  return <div style={style}>9:41</div>;
                }
                """
            ),
            GeneratedFile(
                path: "pages/ScreenSettings.tsx",
                content: """
                import { SlidersHorizontal, ChevronRight } from "lucide-react";
                import { StatusBar } from "../components/StatusBar";

                export function ScreenSettings() {
                  return (
                    <div>
                      <StatusBar />
                      <SlidersHorizontal size={20} />
                      <ChevronRight size={16} />
                    </div>
                  );
                }
                """
            ),
        ]
        let html = ReactHarnessBuilder.buildHTML(
            from: files,
            componentName: "ScreenSettings",
            viewportWidth: 400,
            iconFontRelativePath: "../../Sources/Woodcase/IconFonts/Fonts",
            iconFontDir: iconFontDir
        )
        // Icons from the page file should be extracted and stubbed with codepoints
        #expect(html.contains("const SlidersHorizontal = __iconGlyph__(\"lucide\", { regular: \"\\u{"))
        #expect(html.contains("const ChevronRight = __iconGlyph__(\"lucide\", { regular: \"\\u{"))
    }
}
