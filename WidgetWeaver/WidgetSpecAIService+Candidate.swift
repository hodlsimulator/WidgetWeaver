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

        let warnings = result.usedModel ? [] : [result.note]

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

        case (let old?, nil):
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
        case (let b?, nil):
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
}
