//
//  FeatureFlags.swift
//  WidgetWeaver
//
//  Created by . . on 1/7/26.
//

import Foundation

/// Central feature flag registry.
///
/// Flags are implemented as UserDefaults-backed booleans so a misbehaving surface can be
/// force-disabled without ripping out code.
enum FeatureFlags {
    enum Keys {
        static let contextAwareEditorToolSuiteEnabled = "widgetweaver.feature.editor.contextAwareToolSuite.enabled"

        // Photo Suite / Poster UX rollout.
        static let posterSuiteEnabled = "widgetweaver.feature.editor.posterSuite.enabled"
    }

    /// Default state for the context-aware editor tool suite.
    ///
    /// When `false`, the editor surfaces fall back to a legacy “capabilities-only” tool list:
    /// - no selection intersection policy
    /// - no focus gating
    /// - no availability gating (Smart Photo presence / Photos permission)
    static let defaultContextAwareEditorToolSuiteEnabled: Bool = true

    static var contextAwareEditorToolSuiteEnabled: Bool {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.contextAwareEditorToolSuiteEnabled) == nil {
            return defaultContextAwareEditorToolSuiteEnabled
        }

        return defaults.bool(forKey: Keys.contextAwareEditorToolSuiteEnabled)
    }

    static func setContextAwareEditorToolSuiteEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.contextAwareEditorToolSuiteEnabled)
    }

    static func clearContextAwareEditorToolSuiteOverride() {
        UserDefaults.standard.removeObject(forKey: Keys.contextAwareEditorToolSuiteEnabled)
    }

    /// Default state for the Photo Suite / Poster-specific editor surfaces.
    ///
    /// When `false`, poster-specific editing is available only through the existing generic tools.
    /// When `true`, the editor may expose poster-only controls and/or a dedicated Poster tool.
    static let defaultPosterSuiteEnabled: Bool = false

    static var posterSuiteEnabled: Bool {
        let defaults = UserDefaults.standard

        if defaults.object(forKey: Keys.posterSuiteEnabled) == nil {
            return defaultPosterSuiteEnabled
        }

        return defaults.bool(forKey: Keys.posterSuiteEnabled)
    }

    static func setPosterSuiteEnabled(_ enabled: Bool) {
        UserDefaults.standard.set(enabled, forKey: Keys.posterSuiteEnabled)
    }

    static func clearPosterSuiteOverride() {
        UserDefaults.standard.removeObject(forKey: Keys.posterSuiteEnabled)
    }
}
