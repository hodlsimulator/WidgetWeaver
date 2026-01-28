//
//  WidgetSpecNormaliser.swift
//  WidgetWeaver
//
//  Created by . . on 1/28/26.
//

import Foundation

/// AI-only guardrails applied to generated/patched `WidgetSpec` values before saving.
///
/// `WidgetSpec.normalised()` preserves broad editor flexibility by design.
/// This helper adds conservative clamps and finite-value sanitisation so AI outputs
/// cannot introduce extreme or non-finite numeric values.
public enum WidgetSpecNormaliser {

    public static func normalisedAIOutput(_ spec: WidgetSpec) -> WidgetSpec {
        var s = spec.normalised()

        // Layout (AI-controlled)
        var layout = s.layout
        let spacingBefore = layout.spacing
        let spacingAfter = finite(spacingBefore, fallback: LayoutSpec.defaultLayout.spacing)
            .clamped(to: Limits.layoutSpacing)
        debugLogIfChanged(
            field: "layout.spacing",
            before: spacingBefore,
            after: spacingAfter,
            limits: Limits.layoutSpacing,
            fallback: LayoutSpec.defaultLayout.spacing
        )
        layout.spacing = spacingAfter
        s.layout = layout

        // Style (AI-controlled)
        var style = s.style

        let paddingBefore = style.padding
        let paddingAfter = finite(paddingBefore, fallback: StyleSpec.defaultStyle.padding)
            .clamped(to: Limits.stylePadding)
        debugLogIfChanged(
            field: "style.padding",
            before: paddingBefore,
            after: paddingAfter,
            limits: Limits.stylePadding,
            fallback: StyleSpec.defaultStyle.padding
        )
        style.padding = paddingAfter

        let cornerRadiusBefore = style.cornerRadius
        let cornerRadiusAfter = finite(cornerRadiusBefore, fallback: StyleSpec.defaultStyle.cornerRadius)
            .clamped(to: Limits.styleCornerRadius)
        debugLogIfChanged(
            field: "style.cornerRadius",
            before: cornerRadiusBefore,
            after: cornerRadiusAfter,
            limits: Limits.styleCornerRadius,
            fallback: StyleSpec.defaultStyle.cornerRadius
        )
        style.cornerRadius = cornerRadiusAfter

        s.style = style

        // Symbol (AI-controlled)
        if var sym = s.symbol {
            let sizeBefore = sym.size
            let sizeAfter = finite(sizeBefore, fallback: 18)
                .clamped(to: Limits.symbolSize)
            debugLogIfChanged(
                field: "symbol.size",
                before: sizeBefore,
                after: sizeAfter,
                limits: Limits.symbolSize,
                fallback: 18
            )
            sym.size = sizeAfter
            s.symbol = sym.normalised()
        }

        // Re-run baseline normalisation after clamps.
        return s.normalised()
    }

    // MARK: - Helpers

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

    #if DEBUG
    private static func debugLogIfChanged(
        field: String,
        before: Double,
        after: Double,
        limits: ClosedRange<Double>,
        fallback: Double
    ) {
        guard !equalsDebug(before, after) else { return }

        let beforeText = debugDescribe(before)
        let afterText = debugDescribe(after)
        let rangeText = "\(debugDescribe(limits.lowerBound))...\(debugDescribe(limits.upperBound))"
        let fallbackText = debugDescribe(fallback)

        print("AI Normaliser: \(field) \(beforeText) → \(afterText) (limits \(rangeText), fallback \(fallbackText))")
    }
    #else
    private static func debugLogIfChanged(
        field: String,
        before: Double,
        after: Double,
        limits: ClosedRange<Double>,
        fallback: Double
    ) {
        // DEBUG only.
    }
    #endif

    #if DEBUG
    private static func equalsDebug(_ a: Double, _ b: Double) -> Bool {
        if !a.isFinite || !b.isFinite { return false }
        return a == b
    }

    private static func debugDescribe(_ value: Double) -> String {
        if value.isNaN { return "NaN" }
        if value == .infinity { return "+Inf" }
        if value == -.infinity { return "-Inf" }
        return String(format: "%.3f", value)
    }
    #endif

    // MARK: - Limits

    private enum Limits {
        // Matches existing spec/layout normalisation.
        static let layoutSpacing: ClosedRange<Double> = 0...32

        // Matches current editor controls.
        static let stylePadding: ClosedRange<Double> = 0...40
        static let styleCornerRadius: ClosedRange<Double> = 0...44

        // Matches `SymbolSpec.normalised()`.
        static let symbolSize: ClosedRange<Double> = 8...96
    }
}
