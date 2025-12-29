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

    // One-shot “wake” window consumed by the widget provider.
    private static let clockWakeRequestUntilKey = "widgetweaver.clock.wake.request.until"

    @MainActor
    public static func kickIfNeeded(minIntervalSeconds: TimeInterval = 60 * 10) {
        let defaults = AppGroup.userDefaults
        let now = Date()
        let last = defaults.object(forKey: lastKickKey) as? Date ?? .distantPast
        guard now.timeIntervalSince(last) >= minIntervalSeconds else { return }

        defaults.set(now, forKey: lastKickKey)
        reloadTimelines(includeClock: true)

        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }

    @MainActor
    public static func forceKick() {
        let defaults = AppGroup.userDefaults
        let now = Date()
        defaults.set(now, forKey: lastKickKey)

        reloadTimelines(includeClock: true)

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

    /// Requests a “wake” for the Home Screen clock.
    ///
    /// The widget provider consumes this as a one-shot and starts a burst session if allowed
    /// by the session caps.
    @MainActor
    public static func wakeHomeScreenClock() {
        let defaults = AppGroup.userDefaults
        let now = Date()

        // Short window; the provider only needs a signal that “wake was requested recently”.
        defaults.set(now.addingTimeInterval(60), forKey: clockWakeRequestUntilKey)

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.homeScreenClock)
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
