//
//  WidgetWeaverWidgetRefresh.swift
//  WidgetWeaver
//
//  Created by . . on 12/25/25.
//

import Foundation
import WidgetKit

public enum WidgetWeaverWidgetRefresh {
    private static let lastKickKey = "widgetweaver.widgetRefresh.lastKick"

    @MainActor
    public static func kickIfNeeded(minIntervalSeconds: TimeInterval = 60 * 10) {
        let defaults = AppGroup.userDefaults
        let now = Date()

        let last = defaults.object(forKey: lastKickKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= minIntervalSeconds else { return }

        defaults.set(now, forKey: lastKickKey)

        WidgetCenter.shared.reloadAllTimelines()

        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }

    @MainActor
    public static func forceKick() {
        let defaults = AppGroup.userDefaults
        let now = Date()

        defaults.set(now, forKey: lastKickKey)

        WidgetCenter.shared.reloadAllTimelines()

        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }
}
