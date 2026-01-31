//
//  WidgetWeaverThemeApplier.swift
//  WidgetWeaver
//
//  Created by . . on 1/31/26.
//

import Foundation

/// Applies a curated `WidgetWeaverThemePreset` to a `WidgetSpec` in a single deterministic operation.
///
/// Contract:
/// - Style-only overwrite (no content bindings, no data sources).
/// - Returns a normalised `WidgetSpec`.
public enum WidgetWeaverThemeApplier {

    public static func apply(preset: WidgetWeaverThemePreset, to spec: WidgetSpec) -> WidgetSpec {
        var s = spec

        // Theme application is a strict style overwrite.
        s.style = preset.style.normalised()

        // Optional Clock (Designer) theme application for clock templates.
        if s.layout.template == .clockIcon {
            // Ensure a clock config exists, respecting `WidgetSpec.normalised()` legacy defaults.
            if s.clockConfig == nil {
                s = s.normalised()
            }

            if let raw = preset.clockThemeRaw {
                // Canonicalise using the same behaviour as `WidgetWeaverClockDesignConfig.normalised()`.
                let canonicalTheme = WidgetWeaverClockDesignConfig(
                    theme: raw,
                    face: WidgetWeaverClockDesignConfig.defaultFace
                ).theme

                var config = s.clockConfig ?? WidgetWeaverClockDesignConfig.default
                config.theme = canonicalTheme
                s.clockConfig = config.normalised()
            }
        }

        return s.normalised()
    }
}
