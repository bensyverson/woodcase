//
//  FigmaImportSession+Instance.swift
//  Woodcase
//

extension FigmaImportSession {
    /// An instance as a Pen `ref` to its component, its overrides carried as the ref's
    /// root overrides and descendant overrides; or, when the clip does not carry the
    /// component, a placeholder frame of the instance's size and paint (reported).
    ///
    /// The clipboard carries no instance children — only `symbolData`: the component's
    /// GUID and the overrides, each naming its target by a GUID path through the
    /// component — and `componentPropAssignments`, which a component node consumes through
    /// its `parameterConsumptionMap`.
    mutating func instance(_ record: KiwiRecord, common: inout PenNodeCommon) -> PenNode.Kind {
        guard let symbol = FigmaGUID(record["symbolData"]?["symbolID"]), components.contains(symbol) else {
            report(.missingComponent, .dropped, on: record)
            let size = size(of: record)
            let graphics = graphics(of: record, common: &common)
            return .frame(PenNode.FrameData(
                width: .fixed(size.width), height: .fixed(size.height), cornerRadius: cornerRadius(of: record),
                fills: graphics.fills, stroke: graphics.stroke, strokeWidth: graphics.strokeWidth,
                strokeLinecap: graphics.strokeLinecap, strokeLinejoin: graphics.strokeLinejoin,
                strokeAlignment: graphics.strokeAlignment, effects: graphics.effects, layout: PenLayoutDirection.none
            ))
        }
        var root: [String: AnyCodable] = [:]
        var descendants: [String: [String: AnyCodable]] = [:]
        let instanceSize = size(of: record)
        if let master = tree.records[symbol] {
            let masterSize = size(of: master)
            if instanceSize.width != masterSize.width { root["width"] = .double(instanceSize.width) }
            if instanceSize.height != masterSize.height { root["height"] = .double(instanceSize.height) }
        }
        for value in record["symbolData"]?["symbolOverrides"]?.arrayValue ?? [] {
            guard let override = value.recordValue else { continue }
            let path = (override["guidPath"]?["guids"]?.arrayValue ?? []).compactMap(FigmaGUID.init)
            let isRoot = path.isEmpty || path == [symbol]
            var properties = overrideProperties(override, on: record)
            if isRoot {
                if let enabled = properties.removeValue(forKey: "enabled") { common.enabled = enabled == .bool(false) ? .literal(false) : nil }
                if case let .double(opacity)? = properties.removeValue(forKey: "opacity") { common.opacity = .literal(opacity) }
                root.merge(properties) { $1 }
            } else if !properties.isEmpty {
                descendants[path.map(\.penID).joined(separator: "/"), default: [:]].merge(properties) { $1 }
            }
        }
        applyPropertyAssignments(of: record, symbol: symbol, to: &descendants)
        return .ref(PenNode.RefData(
            ref: symbol.penID,
            descendants: descendants.isEmpty ? nil : descendants.mapValues { PenDescendantOverride(properties: $0) },
            rootOverrides: root.isEmpty ? nil : root
        ))
    }

    /// One symbol override's fields as Pen properties; a field Pen has no property for is
    /// reported.
    private mutating func overrideProperties(_ override: KiwiRecord, on record: KiwiRecord) -> [String: AnyCodable] {
        var properties: [String: AnyCodable] = [:]
        for (field, value) in override.fields.sorted(by: { $0.key < $1.key }) {
            switch field {
            case "guidPath", "name", "overrideLevel":
                continue
            case "fillPaints":
                properties["fill"] = encoded(paints(value, on: record) ?? .multiple([]))
            case "strokePaints":
                properties["stroke"] = encoded(paints(value, on: record) ?? .multiple([]))
            case "visible":
                properties["enabled"] = .bool(value.boolValue ?? true)
            case "opacity":
                properties["opacity"] = .double(value.doubleValue ?? 1)
            case "textData":
                properties["content"] = .string(value["characters"]?.stringValue ?? "")
            case "overriddenSymbolID":
                report(.instanceSwap, .dropped, on: record)
            default:
                report(.instanceOverride, .dropped, on: record, detail: field)
            }
        }
        return properties
    }

    /// The instance's component property values, written as overrides of the component
    /// nodes that consume them: a text property as `content`, a boolean as `enabled`.
    private mutating func applyPropertyAssignments(
        of record: KiwiRecord, symbol: FigmaGUID, to descendants: inout [String: [String: AnyCodable]]
    ) {
        for value in record["componentPropAssignments"]?.arrayValue ?? [] {
            guard let definition = FigmaGUID(value["defID"]) else { continue }
            let assigned = value["value"]
            for guid in tree.subtree(symbol).dropFirst() {
                let entries = tree.records[guid]?["parameterConsumptionMap"]?["entries"]?.arrayValue ?? []
                for entry in entries where FigmaGUID(entry["variableData"]?["value"]?["propRefValue"]?["defId"]) == definition {
                    switch entry["variableField"]?.enumName {
                    case "TEXT_DATA":
                        descendants[guid.penID, default: [:]]["content"] = .string(assigned?["textValue"]?["characters"]?.stringValue ?? "")
                    case "VISIBLE":
                        descendants[guid.penID, default: [:]]["enabled"] = .bool(assigned?["boolValue"]?.boolValue ?? true)
                    case let field:
                        report(.instanceOverride, .dropped, on: record, detail: field ?? "component property")
                    }
                }
            }
        }
    }

    /// A value as the JSON a Pen override stores.
    private func encoded(_ value: some Encodable) -> AnyCodable {
        (try? NodePropertyCodec.encode(value)) ?? .null
    }
}
