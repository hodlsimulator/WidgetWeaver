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
        reloadTimelines(includeClock: false)

        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }

    @MainActor
    public static func forceKick() {
        let defaults = AppGroup.userDefaults
        let now = Date()

        defaults.set(now, forKey: lastKickKey)
        reloadTimelines(includeClock: false)

        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }

    @MainActor
    public static func forceKickIncludingClock() {
        let defaults = AppGroup.userDefaults
        let now = Date()

        defaults.set(now, forKey: lastKickKey)
        reloadTimelines(includeClock: true)

        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }

    @MainActor
    private static func reloadTimelines(includeClock: Bool) {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.lockScreenWeather)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.lockScreenNextUp)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.lockScreenSteps)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.homeScreenSteps)

        if includeClock {
            WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.homeScreenClock)
        }
    }
}
