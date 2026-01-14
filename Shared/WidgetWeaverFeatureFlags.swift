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
/// - Defaults are intentionally conservative (disabled).
public enum WidgetWeaverFeatureFlags {
    private enum Keys {
        static let remindersTemplateEnabled = "widgetweaver.feature.template.reminders.enabled"
    }

    public static var remindersTemplateEnabled: Bool {
        AppGroup.userDefaults.bool(forKey: Keys.remindersTemplateEnabled)
    }

    public static func setRemindersTemplateEnabled(_ enabled: Bool) {
        AppGroup.userDefaults.set(enabled, forKey: Keys.remindersTemplateEnabled)
    }
}
