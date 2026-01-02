//
//  ClockWidgetDiagnostics.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

public enum ClockWidgetDiagnostics {
    public static let debugOverlayEnabledKey = "widgetweaver.clock.debug.overlay.enabled"

    public static let widgetRenderLastKey = "widgetweaver.clock.widget.render.last"
    public static let widgetRenderInfoKey = "widgetweaver.clock.widget.render.info"
    public static let widgetRenderCountPrefix = "widgetweaver.clock.widget.render.count."

    public static let fontAvailableKey = "widgetweaver.clock.font.available"
    public static let fontAvailableAtKey = "widgetweaver.clock.font.available.at"
    public static let fontErrorKey = "widgetweaver.clock.font.error"

    public static let timelineBuildLastKey = "widgetweaver.clock.timelineBuild.last"
    public static let timelineBuildCountPrefix = "widgetweaver.clock.timelineBuild.count."

    private static let renderThrottleKey = "widgetweaver.clock.widget.render.throttle"

    public static var isDebugOverlayEnabled: Bool {
        AppGroup.userDefaults.bool(forKey: debugOverlayEnabledKey)
    }

    @MainActor
    public static func setDebugOverlayEnabled(_ enabled: Bool) {
        let defaults = AppGroup.userDefaults
        defaults.set(enabled, forKey: debugOverlayEnabledKey)
        defaults.synchronize()

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.homeScreenClock)
        #endif
    }

    public static func recordWidgetRender(info: String, now: Date = Date()) {
        let defaults = AppGroup.userDefaults

        let last = defaults.object(forKey: renderThrottleKey) as? Date ?? .distantPast
        if now.timeIntervalSince(last) < 20.0 { return }
        defaults.set(now, forKey: renderThrottleKey)

        defaults.set(now, forKey: widgetRenderLastKey)
        defaults.set(info, forKey: widgetRenderInfoKey)

        let day = dayKey(for: now)
        let countKey = widgetRenderCountPrefix + day
        let c = defaults.integer(forKey: countKey)
        defaults.set(c + 1, forKey: countKey)
    }

    public static func recordFontStatus(available: Bool, error: String?) {
        let defaults = AppGroup.userDefaults
        defaults.set(available, forKey: fontAvailableKey)
        defaults.set(Date(), forKey: fontAvailableAtKey)

        let trimmed = (error ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            defaults.removeObject(forKey: fontErrorKey)
        } else {
            defaults.set(trimmed, forKey: fontErrorKey)
        }
    }

    @MainActor
    public static func clear() {
        let defaults = AppGroup.userDefaults
        defaults.removeObject(forKey: widgetRenderLastKey)
        defaults.removeObject(forKey: widgetRenderInfoKey)
        defaults.removeObject(forKey: fontAvailableKey)
        defaults.removeObject(forKey: fontAvailableAtKey)
        defaults.removeObject(forKey: fontErrorKey)
        defaults.removeObject(forKey: renderThrottleKey)
        defaults.synchronize()

        #if canImport(WidgetKit)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.homeScreenClock)
        #endif
    }

    public static func dayKey(for date: Date) -> String {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.year, .month, .day], from: date)
        let y = comps.year ?? 0
        let m = comps.month ?? 0
        let d = comps.day ?? 0
        return String(format: "%04d%02d%02d", y, m, d)
    }

    public static func timelineLastBuild() -> Date? {
        AppGroup.userDefaults.object(forKey: timelineBuildLastKey) as? Date
    }

    public static func timelineBuildCount(for date: Date) -> Int? {
        let defaults = AppGroup.userDefaults
        let key = timelineBuildCountPrefix + dayKey(for: date)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    public static func widgetLastRender() -> Date? {
        AppGroup.userDefaults.object(forKey: widgetRenderLastKey) as? Date
    }

    public static func widgetLastRenderInfo() -> String? {
        AppGroup.userDefaults.string(forKey: widgetRenderInfoKey)
    }

    public static func widgetRenderCount(for date: Date) -> Int? {
        let defaults = AppGroup.userDefaults
        let key = widgetRenderCountPrefix + dayKey(for: date)
        guard defaults.object(forKey: key) != nil else { return nil }
        return defaults.integer(forKey: key)
    }

    public static func fontAvailable() -> Bool? {
        let defaults = AppGroup.userDefaults
        guard defaults.object(forKey: fontAvailableKey) != nil else { return nil }
        return defaults.bool(forKey: fontAvailableKey)
    }

    public static func fontRecordedAt() -> Date? {
        AppGroup.userDefaults.object(forKey: fontAvailableAtKey) as? Date
    }

    public static func fontError() -> String? {
        AppGroup.userDefaults.string(forKey: fontErrorKey)
    }
}
