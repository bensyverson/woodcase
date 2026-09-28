# ``Woodcase``

Parse, resolve, lay out, and render .pen design documents.

## Overview

Woodcase provides a complete pipeline for working with the `.pen` design format — from raw JSON to rendered pixels:

```
.pen JSON → Parse → Resolve Imports → Expand Refs → Resolve Variables → Layout → Render
```

Each stage is a stateless function that transforms a ``PenDocument`` and returns a new one (or, in later stages, layout rectangles and rendered images).

```swift
let document = try PenParser.parse(contentsOf: url)
let imported = PenImportResolver.resolve(document, libraries: ["libs/lib.pen": libDoc])
let expanded = PenRefExpander.expand(imported)
let resolved = PenVariableResolver.resolve(expanded, theme: ["mode": "dark"])
await GoogleFontResolver.shared.prepareFonts(for: resolved)
await RemoteImageResolver.shared.prepareImages(for: resolved)
let rects = PenLayoutEngine.layout(resolved)
let image = PenRenderer.render(resolved, layoutRects: rects, size: CGSize(width: 800, height: 600))
```

All model types conform to `Friendly` (`Codable & Equatable & Hashable & Sendable`), making them safe to pass across concurrency boundaries and straightforward to serialize.

## Topics

### Essentials

- <doc:PenEngine>
- <doc:PenRendering>
- <doc:EditingDocuments>
- <doc:WoodcaseEditor>
- <doc:WoodcaseLint>
- <doc:WoodcaseActivityLog>
- <doc:WoodcaseBatches>
- <doc:WoodcaseScripting>
- <doc:WoodcaseViewer>
- <doc:WoodcasePerformance>
- <doc:PenCodeGen>
- <doc:PenIconFonts>
- <doc:PenGoogleFonts>
- <doc:PenRemoteImages>
- <doc:PenImportNamespaces>
- <doc:PenInteroperability>

### Pipeline Stages

- ``PenParser``
- ``PenImportResolver``
- ``PenRefExpander``
- ``PenNodePatcher``
- ``PenVariableResolver``
- ``PenLayoutEngine``
- ``PenTextMeasurer``
- ``PenTextLines``
- ``PenFontWeight``
- ``PenFontRegistry``
- ``PenRenderer``

### Rendering

- <doc:PenRendering>
- <doc:PenMeshGradients>
- <doc:PenIconFonts>
- <doc:PenGoogleFonts>
- <doc:PenRemoteImages>
- <doc:PenInteroperability>
- ``PenRenderer``
- ``NodeOverrides``
- ``PenColorParser``
- ``PenHexColor``
- ``PenGlyphPaint``
- ``PenGlyphOutlines``
- ``PenIconGlyph``
- ``PenSVGPathParser``
- ``PenBrowserPlaceholder``

### Geometry

- ``PenPath``
- ``PenPathCommand``
- ``PenPoint``

### Google Fonts

- ``GoogleFontResolver``
- ``GoogleFontCache``
- ``GoogleFontMetadata``
- ``GoogleFontError``

### Remote Images

- <doc:PenRemoteImages>
- ``RemoteImageResolver``
- ``RemoteImageCache``

### Networking

- ``RemoteDataFetching``
- ``StandardDataFetcher``
- ``URLSessionDataFetcher``
- ``TrustFallbackDataFetcher``
- ``CurlDataFetcher``
- ``RemoteFetchError``
- ``NetworkFailure``
- ``ProxyEnvironment``
- ``ProxyEndpoint``
- ``ProxyExclusion``

### Editing

- <doc:EditingDocuments>
- ``EditableDocument``
- ``EditOperation``
- ``EditingError``
- ``NameInUse``
- ``NodeAddress``
- ``ResolvedNodeAddress``
- ``NodePropertyCodec``
- ``PenPropertyShape``
- ``PenValueForm``
- ``PenNestedShape``
- ``PenSchema``
- ``PenSchemaTable``
- ``PenID``
- ``SubtreeIDPlan``

### Batches

- <doc:WoodcaseBatches>
- ``BatchOperation``
- ``BatchGuard``
- ``BatchApplier``
- ``BatchReport``
- ``BatchLineResult``
- ``BatchLineStatus``
- ``CreatedNode``
- ``WriteReport``
- ``NodeReport``
- ``CreatedTreeReport``
- ``BatchError``
- ``BatchErrorMessage``
- ``RemedyDialect``
- ``PenSubtreeDecoder``

### Activity Log

- <doc:WoodcaseActivityLog>
- ``ActivityEvent``
- ``ActivityLog``
- ``ActivityLogLocation``
- ``ActivityReader``
- ``ActivityRecorder``
- ``RepositoryIgnoreFile``
- ``WoodcaseHome``

### Sync

- <doc:CRDTArchitecture>
- ``CRDTDocument``
- ``CRDTOperation``
- ``CRDTSnapshot``
- ``OperationLog``
- ``LWWRegister``
- ``LWWPropertyMap``
- ``RGAList``
- ``TreeMoveCRDT``
- ``PeerID``

### Document Model

- ``PenDocument``
- ``PenFormatVersion``
- ``PenFormatWriteRefusal``
- ``PenNode``
- ``PenNodeCommon``
- ``PenMetadata``
- ``PenRect``
- ``PenPlacement``

### Legacy Format Migration

- ``PenLegacyMigrator``
- ``PenMigrationRule``
- ``PenVersionMigrationRule``
- ``PenStrokeMigrationRule``
- ``PenIconMigrationRule``
- ``PenRichTextMigrationRule``
- ``PenGroupMigrationRule``

### Value Types

- ``PenValue``
- ``PenDollarEscape``
- ``PenSizing``
- ``PenPadding``
- ``PenCornerRadius``
- ``PenViewBox``
- ``AnyCodable``
- ``PenExtras``
- ``PenDecodingMode``

### Visual Properties

- ``PenFill``
- ``PenFills``
- ``PenStrokable``
- ``PenStrokeWidth``
- ``PenEffect``
- ``PenEffects``
- ``PenScriptInput``
- ``PenShaderUniform``
- ``PenMeshPoint``

### Variables

- ``PenVariable``
- ``PenVariableType``
- ``PenVariableValue``
- ``PenThemedValue``

### Code Generation

- <doc:PenCodeGen>
- <doc:SwiftUIChurn>
- ``ComponentAnalyzer``
- ``ThemeAnalyzer``
- ``ReactEmitter``
- ``SwiftUIEmitter``
- ``ThemeEmitter``
- ``ComponentDefinition``
- ``ThemeManifest``
- ``GeneratedFile``

### Enumerations

- ``PenLayoutDirection``
- ``PenJustifyContent``
- ``PenAlignItems``
- ``PenLayoutPosition``
- ``PenTextGrowth``
- ``PenTextAlign``
- ``PenTextAlignVertical``
- ``PenStrokeAlign``
- ``PenStrokeJoin``
- ``PenStrokeCap``
- ``PenFillRule``
- ``PenImageFillMode``
- ``PenGradientType``
- ``PenBlendMode``
