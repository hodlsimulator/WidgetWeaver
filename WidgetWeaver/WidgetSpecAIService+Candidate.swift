//
//  WidgetSpecAIService+Candidate.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import Foundation

extension WidgetSpecAIService {

    func generateCandidate(from prompt: String) async -> WidgetSpecAICandidate {
        let result = await generateNewSpec(from: prompt)
        let spec = result.spec.normalised()

        let summary = Self.changeSummaryForGeneratedSpec(spec)
        let warnings = result.usedModel ? [] : [result.note]

        return WidgetSpecAICandidate(
            candidateSpec: spec,
            changeSummary: summary,
            warnings: warnings,
            isFallback: !result.usedModel,
            sourceAvailability: Self.sourceAvailabilityForCandidate()
        )
    }

    func patchCandidate(baseSpec: WidgetSpec, instruction: String) async -> WidgetSpecAICandidate {
        let base = baseSpec.normalised()

        let result = await applyPatch(to: base, instruction: instruction)
        let candidate = result.spec.normalised()

        var summary = Self.changeSummaryForPatch(base: base, candidate: candidate)
        if summary.isEmpty {
            summary = ["No changes."]
        }

        var warnings: [String] = []
        if result.usedModel {
            warnings.append(contentsOf: Self.scopeGuardWarningsForPatch(base: base, candidate: candidate, instruction: instruction))
        } else {
            warnings.append(result.note)
        }

        return WidgetSpecAICandidate(
            candidateSpec: candidate,
            changeSummary: summary,
            warnings: warnings,
            isFallback: !result.usedModel,
            sourceAvailability: Self.sourceAvailabilityForCandidate()
        )
    }
}

// MARK: - Candidate summaries

private extension WidgetSpecAIService {

    static func sourceAvailabilityForCandidate() -> String {
        if WidgetWeaverFeatureFlags.aiEnabled {
            return availabilityMessage()
        }
        return "AI disabled"
    }

    static func changeSummaryForGeneratedSpec(_ spec: WidgetSpec) -> [String] {
        let s = spec.normalised()

        var lines: [String] = []
        lines.reserveCapacity(6)

        lines.append("Name: \(s.name)")
        lines.append("Primary text: \(s.primaryText)")

        if let secondary = s.secondaryText {
            lines.append("Secondary text: \(secondary)")
        } else {
            lines.append("Secondary text: None")
        }

        lines.append(
            "Layout: \(s.layout.axis.displayName), \(s.layout.alignment.displayName), spacing \(formatPoints(s.layout.spacing))"
        )

        lines.append(
            "Style: \(s.style.background.displayName), \(s.style.accent.displayName), padding \(formatPoints(s.style.padding)), radius \(formatPoints(s.style.cornerRadius))"
        )

        if let sym = s.symbol {
            lines.append("Symbol: \(sym.name) (\(formatPoints(sym.size)) pt)")
        } else {
            lines.append("Symbol: None")
        }

        return lines
    }

    static func changeSummaryForPatch(base: WidgetSpec, candidate: WidgetSpec) -> [String] {
        let b = base.normalised()
        let c = candidate.normalised()

        var lines: [String] = []

        if b.name != c.name {
            lines.append("Name: \(b.name) → \(c.name)")
        }

        if b.primaryText != c.primaryText {
            lines.append("Primary text: \(b.primaryText) → \(c.primaryText)")
        }

        if b.secondaryText != c.secondaryText {
            lines.append(describeOptionalTextChange(label: "Secondary text", before: b.secondaryText, after: c.secondaryText))
        }

        if b.layout.axis != c.layout.axis {
            lines.append("Axis: \(b.layout.axis.displayName) → \(c.layout.axis.displayName)")
        }

        if b.layout.alignment != c.layout.alignment {
            lines.append("Alignment: \(b.layout.alignment.displayName) → \(c.layout.alignment.displayName)")
        }

        if !equalsPoints(b.layout.spacing, c.layout.spacing) {
            lines.append("Spacing: \(formatPoints(b.layout.spacing)) → \(formatPoints(c.layout.spacing))")
        }

        if b.layout.primaryLineLimitSmall != c.layout.primaryLineLimitSmall {
            lines.append("Primary line limit (Small): \(b.layout.primaryLineLimitSmall) → \(c.layout.primaryLineLimitSmall)")
        }

        if b.layout.primaryLineLimit != c.layout.primaryLineLimit {
            lines.append("Primary line limit: \(b.layout.primaryLineLimit) → \(c.layout.primaryLineLimit)")
        }

        if b.layout.secondaryLineLimit != c.layout.secondaryLineLimit {
            lines.append("Secondary line limit: \(b.layout.secondaryLineLimit) → \(c.layout.secondaryLineLimit)")
        }

        if b.style.background != c.style.background {
            lines.append("Background: \(b.style.background.displayName) → \(c.style.background.displayName)")
        }

        if b.style.accent != c.style.accent {
            lines.append("Accent: \(b.style.accent.displayName) → \(c.style.accent.displayName)")
        }

        if !equalsPoints(b.style.padding, c.style.padding) {
            lines.append("Padding: \(formatPoints(b.style.padding)) → \(formatPoints(c.style.padding))")
        }

        if !equalsPoints(b.style.cornerRadius, c.style.cornerRadius) {
            lines.append("Corner radius: \(formatPoints(b.style.cornerRadius)) → \(formatPoints(c.style.cornerRadius))")
        }

        if b.style.primaryTextStyle != c.style.primaryTextStyle {
            lines.append("Primary font: \(b.style.primaryTextStyle.displayName) → \(c.style.primaryTextStyle.displayName)")
        }

        if b.style.secondaryTextStyle != c.style.secondaryTextStyle {
            lines.append("Secondary font: \(b.style.secondaryTextStyle.displayName) → \(c.style.secondaryTextStyle.displayName)")
        }

        if b.image != c.image {
            if c.image == nil {
                lines.append("Image: removed")
            } else if b.image == nil {
                lines.append("Image: added")
            } else {
                lines.append("Image: updated")
            }
        }

        lines.append(contentsOf: symbolDiffLines(before: b.symbol, after: c.symbol))

        return lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    static func symbolDiffLines(before: SymbolSpec?, after: SymbolSpec?) -> [String] {
        switch (before, after) {
        case (nil, nil):
            return []

        case (nil, let new?):
            return ["Symbol: added \(new.name)"]

        case (_?, nil):
            return ["Symbol: removed"]

        case (let old?, let new?):
            var out: [String] = []

            if old.name != new.name {
                out.append("Symbol name: \(old.name) → \(new.name)")
            }

            if !equalsPoints(old.size, new.size) {
                out.append("Symbol size: \(formatPoints(old.size)) → \(formatPoints(new.size))")
            }

            if old.weight != new.weight {
                out.append("Symbol weight: \(prettyToken(old.weight.rawValue)) → \(prettyToken(new.weight.rawValue))")
            }

            if old.renderingMode != new.renderingMode {
                out.append("Symbol rendering: \(prettyToken(old.renderingMode.rawValue)) → \(prettyToken(new.renderingMode.rawValue))")
            }

            if old.tint != new.tint {
                out.append("Symbol tint: \(prettyToken(old.tint.rawValue)) → \(prettyToken(new.tint.rawValue))")
            }

            if old.placement != new.placement {
                out.append("Symbol placement: \(prettyPlacement(old.placement)) → \(prettyPlacement(new.placement))")
            }

            return out
        }
    }

    static func describeOptionalTextChange(label: String, before: String?, after: String?) -> String {
        switch (before, after) {
        case (nil, nil):
            return ""
        case (nil, let a?):
            return "\(label): added \(a)"
        case (_?, nil):
            return "\(label): removed"
        case (let b?, let a?):
            return "\(label): \(b) → \(a)"
        }
    }

    static func equalsPoints(_ a: Double, _ b: Double) -> Bool {
        abs(a - b) < 0.0001
    }

    static func formatPoints(_ value: Double) -> String {
        guard value.isFinite else { return "0" }

        let rounded = value.rounded()
        if abs(rounded - value) < 0.0001 {
            return String(Int(rounded))
        }

        return String(format: "%.1f", value)
    }

    static func prettyToken(_ rawValue: String) -> String {
        if rawValue.isEmpty { return rawValue }

        let spaced = rawValue
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")

        return spaced.prefix(1).uppercased() + spaced.dropFirst()
    }

    static func prettyPlacement(_ placement: SymbolPlacementToken) -> String {
        switch placement {
        case .beforeName:
            return "Before name"
        case .aboveName:
            return "Above name"
        }
    }

    // MARK: - Patch scope guard warnings

    enum PatchChangeArea: Int, Hashable, CaseIterable {
        case name = 0
        case primaryText
        case secondaryText
        case axis
        case alignment
        case spacing
        case primaryLineLimitSmall
        case primaryLineLimit
        case secondaryLineLimit
        case background
        case accent
        case padding
        case cornerRadius
        case primaryFont
        case secondaryFont
        case image
        case symbol

        var displayName: String {
            switch self {
            case .name:
                return "Name"
            case .primaryText:
                return "Primary text"
            case .secondaryText:
                return "Secondary text"
            case .axis:
                return "Axis"
            case .alignment:
                return "Alignment"
            case .spacing:
                return "Spacing"
            case .primaryLineLimitSmall:
                return "Primary line limit (Small)"
            case .primaryLineLimit:
                return "Primary line limit"
            case .secondaryLineLimit:
                return "Secondary line limit"
            case .background:
                return "Background"
            case .accent:
                return "Accent"
            case .padding:
                return "Padding"
            case .cornerRadius:
                return "Corner radius"
            case .primaryFont:
                return "Primary font"
            case .secondaryFont:
                return "Secondary font"
            case .image:
                return "Image"
            case .symbol:
                return "Symbol"
            }
        }
    }

    struct SmallPatchRequest {
        let requestedAreas: Set<PatchChangeArea>
        let hasBroadKeywords: Bool

        var isSmall: Bool {
            !requestedAreas.isEmpty && requestedAreas.count <= 2 && !hasBroadKeywords
        }

        var displayLabel: String {
            let ordered = requestedAreas.sorted { $0.rawValue < $1.rawValue }
            return ordered.map { $0.displayName }.joined(separator: " + ")
        }
    }

    static func scopeGuardWarningsForPatch(base: WidgetSpec, candidate: WidgetSpec, instruction: String) -> [String] {
        guard WidgetWeaverFeatureFlags.aiReviewUIEnabled else { return [] }

        let request = smallPatchRequest(from: instruction)
        guard request.isSmall else { return [] }

        let changed = patchChangeAreas(base: base, candidate: candidate)
        let extra = changed.subtracting(request.requestedAreas)

        let extraThreshold = 4
        guard extra.count >= extraThreshold else { return [] }

        let requestedLabel = request.displayLabel
        let sortedExtra = extra.sorted { $0.rawValue < $1.rawValue }
        let previewExtras = Array(sortedExtra.prefix(4))

        let extraCountText = extra.count == 1 ? "1 other area" : "\(extra.count) other areas"
        let extraText = previewExtras.map { $0.displayName }.joined(separator: ", ")
        let suffix = extra.count > previewExtras.count ? ", …" : ""

        return [
            "Small request (\(requestedLabel)), but the candidate also changes \(extraCountText): \(extraText)\(suffix). Review before applying."
        ]
    }

    static func patchChangeAreas(base: WidgetSpec, candidate: WidgetSpec) -> Set<PatchChangeArea> {
        let b = base.normalised()
        let c = candidate.normalised()

        var out: Set<PatchChangeArea> = []

        if b.name != c.name { out.insert(.name) }
        if b.primaryText != c.primaryText { out.insert(.primaryText) }
        if b.secondaryText != c.secondaryText { out.insert(.secondaryText) }

        if b.layout.axis != c.layout.axis { out.insert(.axis) }
        if b.layout.alignment != c.layout.alignment { out.insert(.alignment) }
        if !equalsPoints(b.layout.spacing, c.layout.spacing) { out.insert(.spacing) }

        if b.layout.primaryLineLimitSmall != c.layout.primaryLineLimitSmall { out.insert(.primaryLineLimitSmall) }
        if b.layout.primaryLineLimit != c.layout.primaryLineLimit { out.insert(.primaryLineLimit) }
        if b.layout.secondaryLineLimit != c.layout.secondaryLineLimit { out.insert(.secondaryLineLimit) }

        if b.style.background != c.style.background { out.insert(.background) }
        if b.style.accent != c.style.accent { out.insert(.accent) }
        if !equalsPoints(b.style.padding, c.style.padding) { out.insert(.padding) }
        if !equalsPoints(b.style.cornerRadius, c.style.cornerRadius) { out.insert(.cornerRadius) }

        if b.style.primaryTextStyle != c.style.primaryTextStyle { out.insert(.primaryFont) }
        if b.style.secondaryTextStyle != c.style.secondaryTextStyle { out.insert(.secondaryFont) }

        if b.image != c.image { out.insert(.image) }
        if b.symbol != c.symbol { out.insert(.symbol) }

        return out
    }

    static func smallPatchRequest(from instruction: String) -> SmallPatchRequest {
        let lower = instruction.lowercased()
        let collapsed = collapseWhitespace(lower).trimmingCharacters(in: .whitespacesAndNewlines)

        var canonical = collapsed
        canonical = canonical.replacingOccurrences(of: "\\b(inset|insets)\\b", with: "padding", options: .regularExpression)
        canonical = canonical.replacingOccurrences(of: "\\b(gap|gutter)\\b", with: "spacing", options: .regularExpression)
        canonical = canonical.replacingOccurrences(of: "\\brounded\\s+corners?\\b", with: "radius", options: .regularExpression)
        canonical = canonical.replacingOccurrences(of: "\\brounding\\b", with: "radius", options: .regularExpression)

        let paddingPattern = "(?:\\bpadding\\b|\\bpad\\b)\\s*(?:to\\s*)?(?:=|:)?\\s*([0-9]+(?:\\.[0-9]+)?)"
        let spacingPattern = "(?:\\bspacing\\b|\\bspace\\b)\\s*(?:to\\s*)?(?:=|:)?\\s*([0-9]+(?:\\.[0-9]+)?)"
        let cornerRadiusPattern = "(?:\\bcorner\\s*radius\\b|\\bcornerradius\\b|\\bradius\\b)\\s*(?:to\\s*)?(?:=|:)?\\s*([0-9]+(?:\\.[0-9]+)?)"

        var requested: Set<PatchChangeArea> = []
        if firstDoubleMatch(paddingPattern, in: canonical) != nil { requested.insert(.padding) }
        if firstDoubleMatch(spacingPattern, in: canonical) != nil { requested.insert(.spacing) }
        if firstDoubleMatch(cornerRadiusPattern, in: canonical) != nil { requested.insert(.cornerRadius) }

        let broadKeywords = [
            "background",
            "accent",
            "colour",
            "color",
            "font",
            "text",
            "name",
            "symbol",
            "icon",
            "image",
            "photo",
            "axis",
            "alignment",
            "horizontal",
            "vertical",
            "remove",
            "delete",
            "add",
            "swap",
            "replace"
        ]

        let hasBroad = broadKeywords.contains { containsWord(canonical, word: $0) }

        return SmallPatchRequest(requestedAreas: requested, hasBroadKeywords: hasBroad)
    }

    static func containsWord(_ text: String, word: String) -> Bool {
        guard !word.isEmpty else { return false }
        let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
        return text.range(of: pattern, options: .regularExpression) != nil
    }

    static func firstDoubleMatch(_ pattern: String, in text: String) -> Double? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        guard let match = regex.firstMatch(in: text, options: [], range: range),
              match.numberOfRanges >= 2,
              let numRange = Range(match.range(at: 1), in: text)
        else { return nil }

        return Double(text[numRange])
    }

    static func collapseWhitespace(_ text: String) -> String {
        var out = ""
        out.reserveCapacity(text.count)

        var lastWasSpace = false
        for ch in text {
            if ch.isWhitespace {
                if !lastWasSpace {
                    out.append(" ")
                    lastWasSpace = true
                }
            } else {
                out.append(ch)
                lastWasSpace = false
            }
        }
        return out
    }

}
