//
//  ReactHarnessBuilder.swift
//  Woodcase
//

import Foundation

/// Assembles an HTML document from ``ReactEmitter`` output that can be
/// loaded into a `WKWebView` for visual regression testing.
///
/// The builder produces HTML with relative `<script src>` and `url()` references
/// to JavaScript libraries and font files. The calling test harness writes the
/// HTML to a file on disk alongside those resources, then loads it via
/// `WKWebView.loadFileURL(_:allowingReadAccessTo:)` so the WebView process
/// can read local images, fonts, and scripts.
public enum ReactHarnessBuilder {
    enum BuilderError: Error {
        case missingJSResource(String)
        case componentNotFound(String)
    }

    /// Builds a complete HTML document that renders a single component.
    ///
    /// The returned HTML references JS libraries and font files via relative paths,
    /// expecting the following directory layout relative to where the HTML is written:
    /// ```
    /// <htmlDir>/
    ///   component.html          ← the output of this method
    ///   js/
    ///     react.production.min.js
    ///     react-dom.production.min.js
    ///     babel.min.js
    ///     tailwindcss.js
    ///   Fonts/                   ← optional
    ///     IBMPlexSans[wdth,wght].ttf
    ///     ...
    ///   images/                  ← referenced by emitter output
    ///     generated-*.png
    /// ```
    ///
    /// - Parameters:
    ///   - files: The `[GeneratedFile]` output from ``ReactEmitter/emit(document:components:pages:theme:options:diagnostics:)``.
    ///   - componentName: The name of the component or page to render (e.g. `"ActionButton"`).
    ///   - props: Optional props to pass to the component.
    ///   - viewportWidth: The viewport width in points.
    ///   - viewportHeight: Optional viewport height in points. When provided, the `#root`
    ///     element is constrained to this height with hidden overflow.
    ///   - jsRelativePath: Relative path from the HTML file to the JS resources directory (default: `"js"`).
    ///   - imageRelativePath: Optional relative path from the HTML file to the generated images directory.
    ///   - fontRelativePath: Optional relative path from the HTML file to the font directory.
    ///     When provided, `@font-face` rules reference `.ttf` and `.otf` files at this path,
    ///     and at their own paths under it for the directory's folders.
    ///   - fontDir: Absolute URL to the font directory on disk, used to enumerate font files —
    ///     its own and its folders' — and read each one's family, weights and style from the
    ///     font itself (`ReactHarnessBuilder.FontFace`). Only needed when `fontRelativePath` is set.
    ///   - iconFontRelativePath: Optional relative path from the HTML file to the bundled icon
    ///     fonts (`Sources/Woodcase/IconFonts/Fonts`). With `iconFontDir`, each icon family the
    ///     page imports gets a `@font-face` for its bundled font there, and each icon stub draws
    ///     its family's glyph in it instead of an empty SVG.
    ///   - iconFontDir: Absolute URL to the icon font directory on disk. Only needed when
    ///     `iconFontRelativePath` is set.
    /// - Returns: A complete HTML document string.
    public static func buildHTML(
        from files: [GeneratedFile],
        componentName: String,
        props: [String: String] = [:],
        viewportWidth: Int,
        viewportHeight: Int? = nil,
        jsRelativePath: String = "js",
        imageRelativePath: String? = nil,
        fontRelativePath: String? = nil,
        fontDir: URL? = nil,
        iconFontRelativePath: String? = nil,
        iconFontDir: URL? = nil
    ) -> String {
        // Build @font-face CSS using relative URLs to font files
        let fontCSS: String = if let fontRelativePath, let fontDir {
            buildFontFaceCSS(relativePath: fontRelativePath, fontDir: fontDir)
        } else {
            ""
        }

        // Extract theme.css
        let themeCSS = files.first { $0.path == "theme.css" }?.content ?? ""
        // A designer state's rules live in states.css; without it no state draws.
        let statesCSS = files.first { $0.path == "states.css" }?.content ?? ""

        // Resolve the target component and its transitive dependencies
        let requiredFiles = resolveDependencies(
            for: componentName,
            in: files.filter { $0.path.hasSuffix(".tsx") }
        )

        // Build inlined component code by stripping imports and exports
        var componentCode = ""
        for file in requiredFiles {
            let stripped = stripImportsAndExports(file.content)
            componentCode += "// --- \(file.path) ---\n\(stripped)\n\n"
        }

        // Rewrite image paths if a custom image relative path is provided.
        // The emitter outputs "./images/" which is correct for a standard project layout,
        // but the test harness writes HTML to a subdirectory (e.g. Fixtures/tmp/).
        if let imageRelativePath {
            componentCode = componentCode.replacingOccurrences(
                of: "./images/",
                with: "\(imageRelativePath)/"
            )
        }

        // Build props string for JSX
        let propsString = props.map { "\($0.key)=\"\($0.value)\"" }.joined(separator: " ")
        let componentJSX = propsString.isEmpty
            ? "<\(componentName) />"
            : "<\(componentName) \(propsString) />"

        // Collect icon imports only from the required files
        let icons = iconImports(in: requiredFiles)

        // Build icon stubs: font-glyph-based when the icon fonts are available, SVG fallback otherwise
        let iconStubCode: String
        let iconFontCSS: String
        if iconFontDir != nil, let iconFontRelativePath {
            iconStubCode = buildIconFontStubs(for: icons)
            iconFontCSS = buildIconFontFaceCSS(for: icons, relativePath: iconFontRelativePath)
        } else {
            iconStubCode = icons.map { iconStub($0.local) }.joined(separator: "\n")
            iconFontCSS = ""
        }

        // The component code + render call is placed in a <script type="text/plain">
        // block (not executed by the browser), then read via .textContent and compiled
        // with Babel.transform(). This avoids template literal escaping issues since
        // the Babel JS library itself contains backticks.
        let userCode = """
        // Expose React APIs as globals (UMD build puts them on React object)
        const { createElement, createContext, useContext, useState, useEffect, useRef, useCallback, useMemo, Fragment } = React;

        // Utility: cn (className merge)
        function cn(...classes) {
          return classes.filter(Boolean).join(" ");
        }

        // Icon package stubs
        \(iconStubCode)

        \(componentCode)

        // Render
        const root = ReactDOM.createRoot(document.getElementById("root"));
        root.render(
          React.createElement(function __WoodcaseHarnessRoot__() {
            React.useEffect(() => {
              const signal = () => {
                window.__READY__ = true;
                if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ready) {
                  window.webkit.messageHandlers.ready.postMessage("ready");
                }
              };
              // A cropped image paint (PenImageCrop) draws only once it has measured its
              // image: wait until none is still loading. A timer, not an animation frame,
              // which an offscreen web view never runs.
              const settle = () => {
                if (document.querySelector('[data-pen-image="loading"]')) {
                  setTimeout(settle, 10);
                } else {
                  signal();
                }
              };
              settle();
            }, []);
            return \(componentJSX);
          })
        );
        """

        let jsPath = jsRelativePath

        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=\(viewportWidth), initial-scale=1.0">
        <style>
        \(fontCSS)
        \(iconFontCSS)
        * { margin: 0; padding: 0; box-sizing: border-box; -webkit-font-smoothing: antialiased; }
        \(viewportHeight.map { "#root { height: \($0)px; overflow: hidden; }" } ?? "")
        \(themeCSS)
        \(statesCSS)
        </style>
        <script src="\(jsPath)/react.production.min.js"></script>
        <script src="\(jsPath)/react-dom.production.min.js"></script>
        <script src="\(jsPath)/tailwindcss.js"></script>
        <script src="\(jsPath)/babel.min.js"></script>
        </head>
        <body>
        <div id="root"></div>
        <script id="user-code" type="text/plain">
        \(userCode)
        </script>
        <script>
        try {
          var src = document.getElementById("user-code").textContent;
          var compiled = Babel.transform(src, {
            presets: [
              Babel.availablePresets["typescript"],
              Babel.availablePresets["react"]
            ],
            filename: "component.tsx"
          }).code;
          eval(compiled);
        } catch (e) {
          document.body.innerHTML = "<pre style='color:red'>" + e.message + "\\n" + (e.stack || "") + "</pre>";
          window.__READY__ = true;
          if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.ready) {
            window.webkit.messageHandlers.ready.postMessage("ready");
          }
        }
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Private

    /// Resolves the target component and all its transitive TSX dependencies.
    ///
    /// Discovers dependencies via two mechanisms:
    /// 1. `import { Foo } from "../components/Foo"` statements (page files)
    /// 2. `<Foo` JSX tags that match a known component file stem (component files
    ///    that reference other components via refs)
    private static func resolveDependencies(
        for componentName: String,
        in tsxFiles: [GeneratedFile]
    ) -> [GeneratedFile] {
        // Map component name → file (derive name from filename stem).
        // Page files (pages/) take priority over component files (components/)
        // because pages contain import statements that reference their dependencies.
        var fileByName: [String: GeneratedFile] = [:]
        for file in tsxFiles.sorted(by: { $0.path < $1.path }) {
            let stem = URL(fileURLWithPath: file.path).deletingPathExtension().lastPathComponent
            let isPage = file.path.hasPrefix("pages/")
            if fileByName[stem] == nil || isPage {
                fileByName[stem] = file
            }
        }

        let allComponentNames = Set(fileByName.keys)

        // Parse local imports from each file to get dependency names
        let importPattern: Regex<(Substring, Substring)> =
            /import\s*\{[^}]+\}\s*from\s*"\.\.?\/(?:components\/)?([\w]+)"/

        // Also find JSX tags like <StatusBar that match known component names
        let jsxPattern: Regex<(Substring, Substring)> = /<([A-Z][A-Za-z0-9]+)/

        func dependencies(of file: GeneratedFile) -> [String] {
            var deps: Set<String> = []

            // From import statements
            for match in file.content.matches(of: importPattern) {
                deps.insert(String(match.output.1))
            }

            // From JSX tags matching known component names
            for match in file.content.matches(of: jsxPattern) {
                let tag = String(match.output.1)
                if allComponentNames.contains(tag) {
                    deps.insert(tag)
                }
            }

            return Array(deps)
        }

        // BFS from the target component
        var visited: Set<String> = []
        var queue: [String] = [componentName]
        var ordered: [GeneratedFile] = []

        while !queue.isEmpty {
            let name = queue.removeFirst()
            guard !visited.contains(name) else { continue }
            visited.insert(name)
            guard let file = fileByName[name] else { continue }
            let deps = dependencies(of: file)
            queue.append(contentsOf: deps)
        }

        // Topological sort: dependencies before dependents (DFS)
        var emitted: Set<String> = []
        func emit(_ name: String) {
            guard visited.contains(name), !emitted.contains(name),
                  let file = fileByName[name]
            else { return }
            for dep in dependencies(of: file) {
                emit(dep)
            }
            emitted.insert(name)
            ordered.append(file)
        }
        emit(componentName)

        return ordered
    }

    /// Strips ES module `import` and `export` keywords from TSX source
    /// so it can run in a plain `<script>` context with Babel standalone.
    private static func stripImportsAndExports(_ source: String) -> String {
        var lines: [String] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            // Skip import lines
            if trimmed.hasPrefix("import ") { continue }
            // Strip "export " prefix from function/const declarations
            if trimmed.hasPrefix("export function ") {
                lines.append(String(line).replacingOccurrences(of: "export function ", with: "function "))
            } else if trimmed.hasPrefix("export const ") {
                lines.append(String(line).replacingOccurrences(of: "export const ", with: "const "))
            } else if trimmed.hasPrefix("export default ") {
                lines.append(String(line).replacingOccurrences(of: "export default ", with: ""))
            } else {
                lines.append(String(line))
            }
        }
        return lines.joined(separator: "\n")
    }
}
