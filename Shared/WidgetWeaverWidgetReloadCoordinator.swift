//
//  WidgetWeaverWidgetReloadCoordinator.swift
//  WidgetWeaver
//
//  Created by . . on 1/25/26.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit

/// Coalesces WidgetKit reload requests to avoid unnecessary timeline churn.
///
/// This helper avoids `WidgetCenter.shared.reloadAllTimelines()` by reloading a fixed set of known widget kinds.
/// Reloads are debounced so multiple rapid writes result in one WidgetKit reload burst.
@MainActor
public final class WidgetWeaverWidgetReloadCoordinator {
    public static let shared = WidgetWeaverWidgetReloadCoordinator()

    private var pendingWorkItem: DispatchWorkItem?

    private init() {}

    public func scheduleReloadAllKnownTimelines(debounceSeconds: TimeInterval = 0.35) {
        scheduleReload(kinds: Self.allKnownKinds, debounceSeconds: debounceSeconds)
    }

    public func scheduleReload(kinds: [String], debounceSeconds: TimeInterval = 0.35) {
        pendingWorkItem?.cancel()

        let uniqueKinds: [String] = Array(Set(kinds))
        let delay = max(0.0, debounceSeconds)

        let work = DispatchWorkItem { [uniqueKinds] in
            for kind in uniqueKinds {
                WidgetCenter.shared.reloadTimelines(ofKind: kind)
            }

            if #available(iOS 17.0, *) {
                WidgetCenter.shared.invalidateConfigurationRecommendations()
            }
        }

        pendingWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static let allKnownKinds: [String] = [
        WidgetWeaverWidgetKinds.main,
        WidgetWeaverWidgetKinds.lockScreenWeather,
        WidgetWeaverWidgetKinds.lockScreenNextUp,
        WidgetWeaverWidgetKinds.lockScreenSteps,
        WidgetWeaverWidgetKinds.lockScreenActivity,
        WidgetWeaverWidgetKinds.homeScreenSteps,
        WidgetWeaverWidgetKinds.homeScreenActivity,
        WidgetWeaverWidgetKinds.homeScreenClock,
        WidgetWeaverWidgetKinds.pawPulseLatestCat,
        WidgetWeaverWidgetKinds.noiseMachine,
        WidgetWeaverWidgetKinds.clipboardActions,
        WidgetWeaverWidgetKinds.remindersDebugSpike,
    ]
}
#endif
