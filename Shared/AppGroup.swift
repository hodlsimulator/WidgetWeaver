//
//  AppGroup.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation

public enum AppGroup {
    public static let identifier = "group.com.conornolan.widgetweaver"

    public static var userDefaults: UserDefaults {
        if let ud = UserDefaults(suiteName: identifier) {
            return ud
        }
        assertionFailure("App Group UserDefaults unavailable. Check App Groups entitlement: \(identifier)")
        return .standard
    }
}
