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
        layout.spacing = finite(layout.spacing, fallback: LayoutSpec.defaultLayout.spacing)
            .clamped(to: Limits.layoutSpacing)
        s.layout = layout

        // Style (AI-controlled)
        var style = s.style
        style.padding = finite(style.padding, fallback: StyleSpec.defaultStyle.padding)
            .clamped(to: Limits.stylePadding)
        style.cornerRadius = finite(style.cornerRadius, fallback: StyleSpec.defaultStyle.cornerRadius)
            .clamped(to: Limits.styleCornerRadius)
        s.style = style

        // Symbol (AI-controlled)
        if var sym = s.symbol {
            sym.size = finite(sym.size, fallback: 18)
                .clamped(to: Limits.symbolSize)
            s.symbol = sym.normalised()
        }

        // Re-run baseline normalisation after clamps.
        return s.normalised()
    }

    // MARK: - Helpers

    private static func finite(_ value: Double, fallback: Double) -> Double {
        value.isFinite ? value : fallback
    }

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
