//
//  WidgetSpec+VariableResolutionNow.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import Foundation

// MARK: - Resolve variable templates with an explicit "now"

public extension WidgetSpec {
    /// Resolves variable templates using an explicit time source.
    ///
    /// This is used for views that need live ticking (e.g. photo clock overlays) without relying on
    /// WidgetKit delivering fresh timeline entries exactly on schedule.
    func resolvingVariables(now: Date, using store: WidgetWeaverVariableStore = .shared) -> WidgetSpec {
        // Custom variables are Pro-gated, built-ins are always present.
        var vars: [String: String] = WidgetWeaverEntitlements.isProUnlocked ? store.loadAll() : [:]

        let builtIns = WidgetWeaverVariableTemplate.builtInVariables(now: now)
        for (k, v) in builtIns where vars[k] == nil {
            vars[k] = v
        }

        // Weather variables behave like built-ins (not Pro-gated).
        // These intentionally override any existing keys to keep the widget truthful.
        let weatherVars = WidgetWeaverWeatherStore.shared.variablesDictionary(now: now)
        for (k, v) in weatherVars {
            vars[k] = v
        }

        // Steps variables behave like built-ins (not Pro-gated).
        // These intentionally override any existing keys to keep the widget truthful.
        let stepsVars = WidgetWeaverStepsStore.shared.variablesDictionary(now: now)
        for (k, v) in stepsVars {
            vars[k] = v
        }

        // Activity variables behave like built-ins (not Pro-gated).
        // These intentionally override any existing keys to keep the widget truthful.
        let activityVars = WidgetWeaverActivityStore.shared.variablesDictionary(now: now)
        for (k, v) in activityVars {
            vars[k] = v
        }

        return resolvingVariables(using: vars, now: now)
    }
}
