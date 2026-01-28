//
//  WidgetSpec+VariableResolutionNow.swift
//  WidgetWeaver
//
//  Created by . . on 1/18/26.
//

import Foundation

private enum SmartPhotoYearBuiltIn {
    static let key = "__smartphoto_year"

    static func yearString(from spec: WidgetSpec) -> String? {
        guard let image = spec.image else { return nil }
        guard let sp = image.smartPhoto else { return nil }

        let mf = (sp.shuffleManifestFileName ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard !mf.isEmpty else { return nil }
        guard let manifest = SmartPhotoShuffleManifestStore.load(fileName: mf) else { return nil }
        guard let entry = manifest.entryForRender() else { return nil }

        return yearString(flags: entry.flags)
    }

    static func yearString(flags: [String]) -> String? {
        for raw in flags {
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard t.hasPrefix("year:") else { continue }

            let tail = t.dropFirst("year:".count)
            let yearText = String(tail).trimmingCharacters(in: .whitespacesAndNewlines)

            guard let year = Int(yearText) else { continue }
            guard year >= 1900 && year <= 2200 else { continue }
            return String(year)
        }

        return nil
    }
}

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

        if let year = SmartPhotoYearBuiltIn.yearString(from: self) {
            vars[SmartPhotoYearBuiltIn.key] = year
        }

        return resolvingVariables(using: vars, now: now)
    }
}
