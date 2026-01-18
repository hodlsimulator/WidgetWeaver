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
    }

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
}
