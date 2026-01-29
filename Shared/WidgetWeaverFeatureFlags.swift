//
//  WidgetWeaverFeatureFlags.swift
//  WidgetWeaver
//
//  Created by . . on 1/14/26.
//

import Foundation

/// Shared (App Group) feature flags.
///
/// Notes:
/// - Stored in the App Group so the app + widget extension see the same values.
/// - Defaults should match shipped behaviour on fresh installs.
public enum WidgetWeaverFeatureFlags {
    private enum Keys {
        static let remindersTemplateEnabled = "widgetweaver.feature.template.reminders.enabled"
        static let clipboardActionsEnabled = "widgetweaver.feature.clipboardActions.enabled"
        static let pawPulseEnabled = "widgetweaver.feature.pawpulse.enabled"

        static let photoFiltersEnabled = "widgetweaver.feature.photoFilters.enabled"

        static let segmentedRingDiagnosticsEnabled = "widgetweaver.feature.clock.segmentedRingDiagnostics.enabled"

        static let aiEnabled = "widgetweaver.feature.ai.enabled"
        static let aiReviewUIEnabled = "widgetweaver.feature.ai.reviewUI.enabled"
    }

    // MARK: - AI

    /// Master kill-switch for all AI surfaces.
    ///
    /// Important:
    /// - `bool(forKey:)` returns `false` when a key is missing.
    /// - Using `object(forKey:)` allows distinguishing “unset” from “explicit false”.
    ///
    /// Default is `true` to match shipped behaviour on fresh installs.
    public static var aiEnabled: Bool {
        if let v = AppGroup.userDefaults.object(forKey: Keys.aiEnabled) as? Bool {
            return v
        }
        return true
    }

    public static func setAIEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: Keys.aiEnabled)
    }

    public static func resetAIEnabledOverride() {
        AppGroup.userDefaults.removeObject(forKey: Keys.aiEnabled)
    }

    /// Review-before-apply UI for AI changes.
    ///
    /// When enabled, AI actions should return a candidate result that can be reviewed before saving.
    ///
    /// Default is `false` so installs that have not opted in keep legacy auto-apply behaviour.
    public static var aiReviewUIEnabled: Bool {
        if let v = AppGroup.userDefaults.object(forKey: Keys.aiReviewUIEnabled) as? Bool {
            return v
        }
        return false
    }

    public static func setAIReviewUIEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: Keys.aiReviewUIEnabled)
    }

    public static func resetAIReviewUIEnabledOverride() {
        AppGroup.userDefaults.removeObject(forKey: Keys.aiReviewUIEnabled)
    }

    // MARK: - Templates

    /// Reminders template visibility.
    ///
    /// Important:
    /// - `bool(forKey:)` returns `false` when a key is missing.
    /// - Using `object(forKey:)` allows distinguishing “unset” from “explicit false”.
    public static var remindersTemplateEnabled: Bool {
        if let v = AppGroup.userDefaults.object(forKey: Keys.remindersTemplateEnabled) as? Bool {
            return v
        }
        return true
    }

    public static func setRemindersTemplateEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: Keys.remindersTemplateEnabled)
    }

    public static func resetRemindersTemplateEnabledOverride() {
        AppGroup.userDefaults.removeObject(forKey: Keys.remindersTemplateEnabled)
    }

    // MARK: - Clock

    /// Debug overlay for the Segmented clock face outer ring.
    ///
    /// When enabled:
    /// - Alternate segment fills and per-segment markers are drawn.
    /// - Intended for verifying the Canvas/CGPath renderer path in WidgetKit.
    ///
    /// Default is `false` so shipped behaviour remains unchanged.
    public static var segmentedRingDiagnosticsEnabled: Bool {
        if let v = AppGroup.userDefaults.object(forKey: Keys.segmentedRingDiagnosticsEnabled) as? Bool {
            return v
        }
        return false
    }

    public static func setSegmentedRingDiagnosticsEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: Keys.segmentedRingDiagnosticsEnabled)
    }

    public static func resetSegmentedRingDiagnosticsEnabledOverride() {
        AppGroup.userDefaults.removeObject(forKey: Keys.segmentedRingDiagnosticsEnabled)
    }

    // MARK: - Clipboard Actions (Screen Actions scope cut)

    /// Clipboard Actions widget + related automation surfaces.
    ///
    /// Default is `false` to keep the shipping surface area minimal unless explicitly enabled.
    public static var clipboardActionsEnabled: Bool {
        if let v = AppGroup.userDefaults.object(forKey: Keys.clipboardActionsEnabled) as? Bool {
            return v
        }
        return false
    }

    public static func setClipboardActionsEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: Keys.clipboardActionsEnabled)
    }

    public static func resetClipboardActionsEnabledOverride() {
        AppGroup.userDefaults.removeObject(forKey: Keys.clipboardActionsEnabled)
    }

    // MARK: - PawPulse (future feature)

    /// PawPulse adoption feed surfaces (future feature).
    ///
    /// Default is `false` so fresh installs do not run background refresh work.
    public static var pawPulseEnabled: Bool {
        if let v = AppGroup.userDefaults.object(forKey: Keys.pawPulseEnabled) as? Bool {
            return v
        }
        return false
    }

    public static func setPawPulseEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: Keys.pawPulseEnabled)
    }

    public static func resetPawPulseEnabledOverride() {
        AppGroup.userDefaults.removeObject(forKey: Keys.pawPulseEnabled)
    }

    // MARK: - Photo Filters (future feature)

    /// Photo filter support for images.
    ///
    /// Default is `false` so the render path remains unchanged unless explicitly enabled.
    public static var photoFiltersEnabled: Bool {
        if let v = AppGroup.userDefaults.object(forKey: Keys.photoFiltersEnabled) as? Bool {
            return v
        }
        return false
    }

    public static func setPhotoFiltersEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: Keys.photoFiltersEnabled)
    }

    public static func resetPhotoFiltersEnabledOverride() {
        AppGroup.userDefaults.removeObject(forKey: Keys.photoFiltersEnabled)
    }
}
