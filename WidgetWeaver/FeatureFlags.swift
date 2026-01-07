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
}
