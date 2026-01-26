//
//  WidgetWeaverEditorTextToolSection.swift
//  WidgetWeaver
//
//  Created by . . on 1/25/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverEditorTextToolSection: View {
    @Binding var designName: String
    @Binding var primaryText: String
    @Binding var secondaryText: String

    let matchedSetEnabled: Bool
    let editingFamilyLabel: String
    let isProUnlocked: Bool
    let onOpenVariables: (() -> Void)?

    @FocusState private var focusedField: FocusedField?
    @State private var showInsertPicker: Bool = false
    @State private var insertTarget: InsertTarget = .primary

    init(
        designName: Binding<String>,
        primaryText: Binding<String>,
        secondaryText: Binding<String>,
        matchedSetEnabled: Bool,
        editingFamilyLabel: String,
        isProUnlocked: Bool,
        onOpenVariables: (() -> Void)? = nil
    ) {
        self._designName = designName
        self._primaryText = primaryText
        self._secondaryText = secondaryText
        self.matchedSetEnabled = matchedSetEnabled
        self.editingFamilyLabel = editingFamilyLabel
        self.isProUnlocked = isProUnlocked
        self.onOpenVariables = onOpenVariables
    }

    private enum FocusedField: Hashable {
        case designName
        case primaryText
        case secondaryText
    }

    private enum InsertTarget: Hashable {
        case primary
        case secondary
    }

    var body: some View {
        Section {
            TextField("Design name", text: $designName)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("EditorTextField.DesignName")
                .focused($focusedField, equals: .designName)

            variableTextFieldRow(
                title: "Primary text",
                text: $primaryText,
                focusedFieldValue: .primaryText,
                insertTarget: .primary,
                accessibilityID: "EditorTextField.PrimaryText"
            )

            templateFeedbackRows(for: primaryText, fieldID: "PrimaryText")

            variableTextFieldRow(
                title: "Secondary text (optional)",
                text: $secondaryText,
                focusedFieldValue: .secondaryText,
                insertTarget: .secondary,
                accessibilityID: "EditorTextField.SecondaryText"
            )

            templateFeedbackRows(for: secondaryText, fieldID: "SecondaryText")

            if matchedSetEnabled {
                Text("Text fields are currently editing: \(editingFamilyLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Text")
        } footer: {
            Text("Tap \(Image(systemName: "curlybraces.square")) to insert variables. Preview appears when templates are detected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showInsertPicker) {
            NavigationStack {
                WidgetWeaverVariableInsertPickerView(
                    isProUnlocked: isProUnlocked,
                    customVariables: WidgetWeaverVariableStore.shared.loadAll(),
                    onInsert: { snippet in
                        insertSnippet(snippet)
                    }
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .primaryText || focusedField == .secondaryText {
                    Spacer()

                    Button {
                        openInsertPickerForFocusedField()
                    } label: {
                        Label("Insert variable", systemImage: "curlybraces.square")
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        let headerID = "EditorSectionHeader." + title.replacingOccurrences(of: " ", with: "_")

        return Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityIdentifier(headerID)
    }

    private func templateFeedbackRows(for raw: String, fieldID: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasDelimiters = trimmed.contains("{{") || trimmed.contains("}}")
        let isUnbalanced = hasDelimiters && hasUnbalancedTemplateDelimiters(trimmed)
        let isTimeDependent = hasDelimiters && !isUnbalanced && WidgetWeaverVariableTemplate.isTimeDependentTemplate(trimmed)

        let alignedStart = WidgetWeaverRenderClock.alignedTimelineStartDate(
            interval: 1.0,
            now: WidgetWeaverRenderClock.now
        )

        return Group {
            if !hasDelimiters {
                EmptyView()
            } else if isUnbalanced {
                Label("Unbalanced {{ }} delimiters", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("EditorTextField.TemplateWarning.\(fieldID)")
            } else if isTimeDependent {
                TimelineView(.periodic(from: alignedStart, by: 1.0)) { ctx in
                    templatePreviewRow(template: trimmed, now: ctx.date, fieldID: fieldID)
                }

                templateDiagnosticsRows(template: trimmed, fieldID: fieldID)
            } else {
                templatePreviewRow(template: trimmed, now: WidgetWeaverRenderClock.now, fieldID: fieldID)

                templateDiagnosticsRows(template: trimmed, fieldID: fieldID)
            }
        }
    }

    private func templateDiagnosticsRows(template: String, fieldID: String) -> some View {
        let builtInValues = TemplateKeyDiagnostics.currentBuiltInValues(now: WidgetWeaverRenderClock.now)

        let customKeys: Set<String> = {
            let vars = WidgetWeaverVariableStore.shared.loadAll()
            return Set(vars.keys.map { WidgetWeaverVariableStore.canonicalKey($0) })
        }()

        let report = TemplateKeyDiagnostics.report(
            template: template,
            isProUnlocked: isProUnlocked,
            customKeys: customKeys,
            builtInValues: builtInValues
        )

        return Group {
            if !report.unknownBuiltInKeys.isEmpty {
                templateIssueRow(
                    title: "Unknown built-in key",
                    systemImage: "questionmark.circle.fill",
                    keySummary: summarisedKeys(report.unknownBuiltInKeys),
                    copyPayload: report.unknownBuiltInKeys.sorted().joined(separator: "\n"),
                    actionTitle: nil,
                    action: nil,
                    fieldID: fieldID,
                    kindID: "UnknownBuiltIn"
                )
            }

            if !report.unavailableBuiltInKeys.isEmpty {
                templateIssueRow(
                    title: "Built-in key currently unavailable",
                    systemImage: "exclamationmark.triangle.fill",
                    keySummary: summarisedKeys(report.unavailableBuiltInKeys),
                    copyPayload: report.unavailableBuiltInKeys.sorted().joined(separator: "\n"),
                    actionTitle: nil,
                    action: nil,
                    fieldID: fieldID,
                    kindID: "UnavailableBuiltIn"
                )
            }

            if !report.proLockedCustomKeys.isEmpty {
                templateIssueRow(
                    title: "Custom variables require Pro",
                    systemImage: "lock.fill",
                    keySummary: summarisedKeys(report.proLockedCustomKeys),
                    copyPayload: report.proLockedCustomKeys.sorted().joined(separator: "\n"),
                    actionTitle: onOpenVariables == nil ? nil : "Open Variables",
                    action: onOpenVariables == nil ? nil : { openVariablesFromDiagnostics() },
                    fieldID: fieldID,
                    kindID: "ProLockedCustom"
                )
            } else if !report.missingCustomKeys.isEmpty {
                templateIssueRow(
                    title: "Missing variables",
                    systemImage: "exclamationmark.circle.fill",
                    keySummary: summarisedKeys(report.missingCustomKeys),
                    copyPayload: report.missingCustomKeys.sorted().joined(separator: "\n"),
                    actionTitle: onOpenVariables == nil ? nil : "Open Variables",
                    action: onOpenVariables == nil ? nil : { openVariablesFromDiagnostics() },
                    fieldID: fieldID,
                    kindID: "MissingCustom"
                )
            }
        }
    }

    private func openVariablesFromDiagnostics() {
        showInsertPicker = false
        focusedField = nil
        onOpenVariables?()
    }

    private func summarisedKeys(_ keys: [String], max: Int = 3) -> String {
        let unique = Array(Set(keys)).sorted()
        guard !unique.isEmpty else { return "" }

        if unique.count <= max {
            return unique.joined(separator: ", ")
        }

        let head = unique.prefix(max).joined(separator: ", ")
        let rest = unique.count - max
        return "\(head) +\(rest) more"
    }

    private func templateIssueRow(
        title: String,
        systemImage: String,
        keySummary: String,
        copyPayload: String,
        actionTitle: String?,
        action: (() -> Void)?,
        fieldID: String,
        kindID: String
    ) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    if !keySummary.isEmpty {
                        Text(keySummary)
                            .font(.system(.caption2, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            } icon: {
                Image(systemName: systemImage)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Button {
                UIPasteboard.general.string = copyPayload
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy keys")

            if let actionTitle, let action {
                Button(actionTitle) {
                    action()
                }
                .buttonStyle(.borderless)
                .font(.caption)
            }
        }
        .accessibilityIdentifier("EditorTextField.TemplateIssue.\(fieldID).\(kindID)")
    }

    private func templatePreviewRow(template: String, now: Date, fieldID: String) -> some View {
        let rendered = renderTemplatePreview(template, now: now)

        return VStack(alignment: .leading, spacing: 6) {
            Text("Preview")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(rendered.isEmpty ? "—" : rendered)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .contextMenu {
            Button("Copy preview") {
                UIPasteboard.general.string = rendered
            }
        }
        .accessibilityIdentifier("EditorTextField.TemplatePreview.\(fieldID)")
    }

    private func variableTextFieldRow(
        title: String,
        text: Binding<String>,
        focusedFieldValue: FocusedField,
        insertTarget: InsertTarget,
        accessibilityID: String
    ) -> some View {
        HStack(spacing: 10) {
            TextField(title, text: text)
                .accessibilityIdentifier(accessibilityID)
                .focused($focusedField, equals: focusedFieldValue)

            Button {
                self.insertTarget = insertTarget
                showInsertPicker = true
            } label: {
                Image(systemName: "curlybraces.square")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Insert variable")
        }
    }

    private func openInsertPickerForFocusedField() {
        switch focusedField {
        case .primaryText:
            insertTarget = .primary
        case .secondaryText:
            insertTarget = .secondary
        default:
            return
        }

        showInsertPicker = true
    }

    private func insertSnippet(_ snippet: String) {
        switch insertTarget {
        case .primary:
            primaryText = appendingSnippet(snippet, to: primaryText)
        case .secondary:
            secondaryText = appendingSnippet(snippet, to: secondaryText)
        }
    }

    private func appendingSnippet(_ snippet: String, to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return snippet
        }

        if let last = text.last, last == "\n" || last == " " {
            return text + snippet
        }

        return text + " " + snippet
    }

    private func renderTemplatePreview(_ template: String, now: Date) -> String {
        var vars: [String: String] = [:]

        if isProUnlocked {
            vars = WidgetWeaverVariableStore.shared.loadAll()
        }

        let builtIns = WidgetWeaverVariableTemplate.builtInVariables(now: now)
        for (k, v) in builtIns where vars[k] == nil {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverWeatherStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverStepsStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverActivityStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        return WidgetWeaverVariableTemplate.render(template, variables: vars, now: now, maxPasses: 3)
    }

    private func hasUnbalancedTemplateDelimiters(_ s: String) -> Bool {
        var balance = 0
        var i = s.startIndex
        let end = s.endIndex

        while i < end {
            let ch = s[i]

            if ch == "{" {
                let next = s.index(after: i)
                if next < end, s[next] == "{" {
                    balance += 1
                    i = s.index(after: next)
                    continue
                }
            } else if ch == "}" {
                let next = s.index(after: i)
                if next < end, s[next] == "}" {
                    if balance == 0 { return true }
                    balance -= 1
                    i = s.index(after: next)
                    continue
                }
            }

            i = s.index(after: i)
        }

        return balance != 0
    }

    // MARK: - Template diagnostics helper

    private enum TemplateKeyDiagnostics {
        struct Report: Hashable {
            var referencedBuiltInKeys: [String]
            var referencedCustomKeys: [String]

            var unknownBuiltInKeys: [String]
            var unavailableBuiltInKeys: [String]
            var missingCustomKeys: [String]
            var proLockedCustomKeys: [String]
        }

        private static let timeKeys: Set<String> = [
            "__now",
            "__now_unix",
            "__today",
            "__time",
            "__weekday",
        ]

        private static let weatherKeys: Set<String> = [
            "__weather_location",
            "__weather_condition",
            "__weather_symbol",
            "__weather_updated_iso",

            "__weather_temp",
            "__weather_temp_c",
            "__weather_temp_f",

            "__weather_feels",
            "__weather_feels_c",
            "__weather_feels_f",

            "__weather_high",
            "__weather_high_c",
            "__weather_high_f",
            "__weather_low",
            "__weather_low_c",
            "__weather_low_f",

            "__weather_precip",
            "__weather_precip_fraction",
            "__weather_humidity",
            "__weather_humidity_fraction",

            "__weather_nowcast",
            "__weather_nowcast_secondary",
            "__weather_rain_start_min",
            "__weather_rain_end_min",
            "__weather_rain_start",
            "__weather_rain_peak_intensity_mmh",
            "__weather_rain_peak_chance",
            "__weather_rain_peak_chance_fraction",

            "__weather_lat",
            "__weather_lon",
        ]

        private static let stepsKeys: Set<String> = [
            "__steps_goal_weekday",
            "__steps_goal_weekend",
            "__steps_goal_today",
            "__steps_streak_rule",

            "__steps_today",
            "__steps_updated_iso",
            "__steps_today_fraction",
            "__steps_today_percent",
            "__steps_goal_hit_today",

            "__steps_streak",
            "__steps_avg_7",
            "__steps_avg_7_exact",
            "__steps_avg_30",
            "__steps_avg_30_exact",
            "__steps_best_day",
            "__steps_best_day_date_iso",
            "__steps_best_day_date",

            "__steps_access",
        ]

        private static let activityKeys: Set<String> = [
            "__activity_access",
            "__activity_updated_iso",
            "__activity_steps_today",
            "__activity_flights_today",

            "__activity_distance_m",
            "__activity_distance_m_exact",
            "__activity_distance_km",
            "__activity_distance_km_exact",

            "__activity_active_energy_kcal",
            "__activity_active_energy_kcal_exact",
        ]

        private static let supportedBuiltInKeys: Set<String> = {
            var set = Set<String>()
            set.formUnion(timeKeys)
            set.formUnion(weatherKeys)
            set.formUnion(stepsKeys)
            set.formUnion(activityKeys)
            return set
        }()

        static func currentBuiltInValues(now: Date) -> [String: String] {
            var out = WidgetWeaverVariableTemplate.builtInVariables(now: now)
            out.merge(WidgetWeaverWeatherStore.shared.variablesDictionary(now: now), uniquingKeysWith: { _, new in new })
            out.merge(WidgetWeaverStepsStore.shared.variablesDictionary(now: now), uniquingKeysWith: { _, new in new })
            out.merge(WidgetWeaverActivityStore.shared.variablesDictionary(now: now), uniquingKeysWith: { _, new in new })
            return out
        }

        static func report(
            template: String,
            isProUnlocked: Bool,
            customKeys: Set<String>,
            builtInValues: [String: String]
        ) -> Report {
            let referenced = referencedCanonicalKeys(in: template)

            var referencedBuiltIns: [String] = []
            var referencedCustom: [String] = []

            var unknownBuiltIns: [String] = []
            var unavailableBuiltIns: [String] = []
            var missingCustom: [String] = []
            var proLockedCustom: [String] = []

            for key in referenced {
                if key.hasPrefix("__") {
                    referencedBuiltIns.append(key)

                    if !supportedBuiltInKeys.contains(key) {
                        unknownBuiltIns.append(key)
                    } else {
                        let value = builtInValues[key]
                        if value == nil || value?.isEmpty == true {
                            unavailableBuiltIns.append(key)
                        }
                    }
                } else {
                    referencedCustom.append(key)

                    if isProUnlocked {
                        if !customKeys.contains(key) {
                            missingCustom.append(key)
                        }
                    } else {
                        proLockedCustom.append(key)
                    }
                }
            }

            return Report(
                referencedBuiltInKeys: referencedBuiltIns,
                referencedCustomKeys: referencedCustom,
                unknownBuiltInKeys: unknownBuiltIns,
                unavailableBuiltInKeys: unavailableBuiltIns,
                missingCustomKeys: missingCustom,
                proLockedCustomKeys: proLockedCustom
            )
        }

        private static func referencedCanonicalKeys(in template: String) -> [String] {
            let raw = template.trimmingCharacters(in: .whitespacesAndNewlines)
            guard raw.contains("{{") else { return [] }

            var out: [String] = []
            out.reserveCapacity(6)
            var seen: Set<String> = []

            var cursor = raw.startIndex
            let end = raw.endIndex

            while cursor < end {
                guard let open = raw.range(of: "{{", range: cursor..<end) else { break }
                guard let close = raw.range(of: "}}", range: open.upperBound..<end) else { break }

                let body = String(raw[open.upperBound..<close.lowerBound])
                if let key = canonicalKeyFromTokenBody(body) {
                    if !seen.contains(key) {
                        seen.insert(key)
                        out.append(key)
                    }
                }

                cursor = close.upperBound
            }

            return out
        }

        private static func canonicalKeyFromTokenBody(_ tokenBody: String) -> String? {
            let token = tokenBody.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !token.isEmpty else { return nil }

            let leftSide: String = {
                if let range = token.range(of: "||") {
                    return String(token[..<range.lowerBound])
                }
                return token
            }()

            let base: String = {
                if let idx = leftSide.firstIndex(of: "|") {
                    return String(leftSide[..<idx])
                }
                return leftSide
            }()
            .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !base.isEmpty else { return nil }
            guard !base.hasPrefix("=") else { return nil }

            let canonical = WidgetWeaverVariableStore.canonicalKey(base)
            return canonical.isEmpty ? nil : canonical
        }
    }
}
