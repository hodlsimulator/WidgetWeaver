//
//  WidgetWeaverVariableTemplateBuilderView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverVariableTemplateBuilderView: View {
    let isProUnlocked: Bool
    let customVariables: [String: String]
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    private enum Style: String, CaseIterable, Identifiable {
        case plain = "Standard"
        case number = "Number"
        case percent = "Percentage"
        case progressBar = "Progress bar"
        case relativeTime = "Relative time"
        case pluralWords = "Plural words"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .plain: return "textformat"
            case .number: return "number"
            case .percent: return "percent"
            case .progressBar: return "chart.bar"
            case .relativeTime: return "clock.arrow.circlepath"
            case .pluralWords: return "textformat.abc"
            }
        }

        var helperText: String {
            switch self {
            case .plain:
                return "Shows the value as-is."
            case .number:
                return "Formats a number using the current locale."
            case .percent:
                return "Treats 0–1 as a fraction (0.42 → 42%)."
            case .progressBar:
                return "Shows a bar using █ and ░."
            case .relativeTime:
                return "Turns a date/time into “2h ago”."
            case .pluralWords:
                return "Chooses singular/plural based on the number."
            }
        }
    }

    @State private var selectedKey: String = "__time"
    @State private var fallback: String = "—"
    @State private var style: Style = .plain

    @State private var numberDecimals: Int = 0
    @State private var percentDecimals: Int = 0
    @State private var barWidth: Int = 10
    @State private var pluralSingular: String = "day"
    @State private var pluralPlural: String = "days"

    @State private var statusMessage: String = ""

    var body: some View {
        List {
            Section {
                NavigationLink {
                    WidgetWeaverVariableKeyChooserView(
                        isProUnlocked: isProUnlocked,
                        customVariables: customVariables,
                        selectedKey: $selectedKey
                    )
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Variable")
                                .font(.caption)
                                .foregroundStyle(.secondary)

                            Text(displayName(for: selectedKey))
                                .font(.headline)
                                .foregroundStyle(.primary)

                            Text(selectedKey)
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 0)

                        Text(currentValueDisplay)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            } header: {
                Text("1. Choose")
            } footer: {
                Text("This picks the key that will go inside {{ }}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                TextField("Fallback (shown when empty)", text: $fallback)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        fallbackChip("—")
                        fallbackChip("0")
                        fallbackChip("--")
                        fallbackChip("None")
                        fallbackChip("N/A")
                        Button {
                            fallback = ""
                        } label: {
                            Label("Clear", systemImage: "xmark.circle")
                                .font(.caption)
                                .padding(.vertical, 6)
                                .padding(.horizontal, 10)
                                .background(.thinMaterial, in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.vertical, 2)
                }
            } header: {
                Text("2. If empty")
            } footer: {
                Text("Fallback prevents blank output when the value is missing.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Picker("Style", selection: $style) {
                    ForEach(Style.allCases) { s in
                        Label(s.rawValue, systemImage: s.systemImage).tag(s)
                    }
                }

                styleOptions

                Text(style.helperText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text("3. Style")
            }

            Section {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Snippet")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(snippet)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)

                    Text("Preview")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(previewOutput.isEmpty ? "—" : previewOutput)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(.primary)
                        .textSelection(.enabled)

                    if !statusMessage.isEmpty {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.vertical, 2)
            }

            Section {
                Button {
                    UIPasteboard.general.string = snippet
                    statusMessage = "Copied snippet."
                } label: {
                    Label("Copy snippet", systemImage: "doc.on.doc")
                }

                Button {
                    onInsert(snippet)
                    dismiss()
                } label: {
                    Label("Insert snippet", systemImage: "arrow.down.circle")
                }
            } footer: {
                Text("Insert adds the snippet to the current text field in this screen. Copy works anywhere.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Build snippet")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
    }

    // MARK: - Derived

    private var resolvedBuiltInValues: [String: String] {
        let now = WidgetWeaverRenderClock.now

        var vars = WidgetWeaverVariableTemplate.builtInVariables(now: now)
        for (k, v) in WidgetWeaverWeatherStore.shared.variablesDictionary(now: now) { vars[k] = v }
        for (k, v) in WidgetWeaverStepsStore.shared.variablesDictionary(now: now) { vars[k] = v }
        for (k, v) in WidgetWeaverActivityStore.shared.variablesDictionary(now: now) { vars[k] = v }

        return vars
    }

    private var previewVariables: [String: String] {
        let builtIns = resolvedBuiltInValues
        if !isProUnlocked { return builtIns }

        var out = builtIns
        for (k, v) in customVariables { out[k] = v }
        return out
    }

    private var currentValueDisplay: String {
        let v = previewVariables[selectedKey] ?? ""
        let trimmed = v.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "—" : trimmed
    }

    private var snippet: String {
        let key = selectedKey.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty else { return "{{}}" }

        let fb = fallback.trimmingCharacters(in: .whitespacesAndNewlines)
        let filters = selectedFilters

        if filters.isEmpty {
            if fb.isEmpty {
                return "{{\(key)}}"
            }
            return "{{\(key)|\(fb)}}"
        }

        let filterPipeline = filters.joined(separator: "|")
        if fb.isEmpty {
            return "{{\(key)||\(filterPipeline)}}"
        }
        return "{{\(key)|\(fb)||\(filterPipeline)}}"
    }

    private var previewOutput: String {
        let now = WidgetWeaverRenderClock.now
        return WidgetWeaverVariableTemplate.render(snippet, variables: previewVariables, now: now, maxPasses: 3)
    }

    private var selectedFilters: [String] {
        switch style {
        case .plain:
            return []

        case .number:
            return ["number:\(numberDecimals.clamped(to: 0...6))"]

        case .percent:
            return ["percent:\(percentDecimals.clamped(to: 0...6))"]

        case .progressBar:
            return ["bar:\(barWidth.clamped(to: 3...40))"]

        case .relativeTime:
            return ["relative"]

        case .pluralWords:
            let singular = pluralSingular.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "item" : pluralSingular
            let plural = pluralPlural.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "items" : pluralPlural
            return ["plural:\(singular):\(plural)"]
        }
    }

    @ViewBuilder
    private var styleOptions: some View {
        switch style {
        case .plain:
            EmptyView()

        case .number:
            Stepper("Decimals: \(numberDecimals)", value: $numberDecimals, in: 0...6)

        case .percent:
            Stepper("Decimals: \(percentDecimals)", value: $percentDecimals, in: 0...6)

        case .progressBar:
            Stepper("Bar width: \(barWidth)", value: $barWidth, in: 3...40)

        case .relativeTime:
            EmptyView()

        case .pluralWords:
            TextField("Singular (1)", text: $pluralSingular)
            TextField("Plural (2+)", text: $pluralPlural)
        }
    }

    // MARK: - UI Helpers

    private func fallbackChip(_ s: String) -> some View {
        Button {
            fallback = s
        } label: {
            Text(s)
                .font(.caption)
                .padding(.vertical, 6)
                .padding(.horizontal, 10)
                .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Set fallback to \(s)")
    }

    private func displayName(for key: String) -> String {
        switch key {
        case "__time": return "Time"
        case "__today": return "Today"
        case "__weekday": return "Weekday"
        case "__now": return "Now (ISO8601)"
        case "__now_unix": return "Now (unix)"
        case "__steps_today": return "Steps today"
        case "__steps_goal_today": return "Steps goal today"
        case "__steps_streak": return "Steps streak"
        case "__activity_steps_today": return "Activity steps today"
        case "__weather_temp": return "Weather temperature"
        case "__weather_condition": return "Weather condition"
        default:
            return key
        }
    }
}

private struct WidgetWeaverVariableKeyChooserView: View {
    let isProUnlocked: Bool
    let customVariables: [String: String]
    @Binding var selectedKey: String

    @Environment(\.dismiss) private var dismiss

    @State private var searchText: String = ""
    @AppStorage("variables.builtins.showAdvanced") private var showAdvancedKeys: Bool = false

    var body: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let includeAdvanced = showAdvancedKeys || !q.isEmpty

        List {
            Section {
                Toggle("Show advanced built-in keys", isOn: $showAdvancedKeys)
            } footer: {
                Text("Searching always includes advanced keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if isProUnlocked {
                let customKeys = customVariables.keys.sorted().filter { matchesQuery($0, q: q) || matchesQuery(customVariables[$0] ?? "", q: q) }
                if !customKeys.isEmpty {
                    Section("Custom") {
                        ForEach(customKeys, id: \.self) { key in
                            keyRow(
                                label: key,
                                key: key,
                                value: customVariables[key] ?? "",
                                isBuiltIn: false
                            )
                        }
                    }
                }
            }

            let builtInKeys = builtInSections(includeAdvanced: includeAdvanced)
            ForEach(builtInKeys) { section in
                let filtered = section.keys.filter { matchesQuery($0, q: q) }
                if !filtered.isEmpty {
                    Section(section.title) {
                        ForEach(filtered, id: \.self) { key in
                            keyRow(
                                label: displayName(for: key),
                                key: key,
                                value: resolvedBuiltInValues[key] ?? "",
                                isBuiltIn: true
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Choose variable")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
    }

    private struct BuiltInSection: Identifiable, Hashable {
        let id: String
        let title: String
        let keys: [String]
    }

    private var resolvedBuiltInValues: [String: String] {
        let now = WidgetWeaverRenderClock.now

        var vars = WidgetWeaverVariableTemplate.builtInVariables(now: now)
        for (k, v) in WidgetWeaverWeatherStore.shared.variablesDictionary(now: now) { vars[k] = v }
        for (k, v) in WidgetWeaverStepsStore.shared.variablesDictionary(now: now) { vars[k] = v }
        for (k, v) in WidgetWeaverActivityStore.shared.variablesDictionary(now: now) { vars[k] = v }

        return vars
    }

    private func builtInSections(includeAdvanced: Bool) -> [BuiltInSection] {
        let values = resolvedBuiltInValues

        let timeKeys = ["__time", "__today", "__weekday", "__now", "__now_unix"]
        let weatherKeys = values.keys.filter { $0.hasPrefix("__weather_") }.sorted()
        let stepsKeys = values.keys.filter { $0.hasPrefix("__steps_") }.sorted()
        let activityKeys = values.keys.filter { $0.hasPrefix("__activity_") }.sorted()

        return [
            BuiltInSection(id: "time", title: "Time", keys: timeKeys.filter { includeAdvanced || !isAdvancedKey($0) }),
            BuiltInSection(id: "weather", title: "Weather", keys: weatherKeys.filter { includeAdvanced || !isAdvancedKey($0) }),
            BuiltInSection(id: "steps", title: "Steps", keys: stepsKeys.filter { includeAdvanced || !isAdvancedKey($0) }),
            BuiltInSection(id: "activity", title: "Activity", keys: activityKeys.filter { includeAdvanced || !isAdvancedKey($0) }),
        ]
    }

    private func isAdvancedKey(_ key: String) -> Bool {
        let allowList: Set<String> = [
            "__time",
            "__today",
            "__weekday",
            "__now",
            "__now_unix",
            "__steps_today",
            "__steps_goal_today",
            "__steps_streak",
            "__activity_steps_today",
            "__weather_temp",
            "__weather_condition"
        ]

        if allowList.contains(key) { return false }

        let k = key.lowercased()

        if k.contains("_exact") { return true }
        if k.contains("_fraction") { return true }
        if k.hasSuffix("_iso") { return true }
        if k.hasSuffix("_unix") { return true }
        if k.hasSuffix("_symbol") { return true }
        if k.contains("_start") || k.contains("_end") || k.contains("_peak") { return true }
        if k.hasSuffix("_access") { return true }
        if k.hasSuffix("_lat") || k.hasSuffix("_lon") { return true }

        if k.hasPrefix("__weather_") { return true }
        if k.hasPrefix("__steps_") { return true }
        if k.hasPrefix("__activity_") { return true }

        return false
    }

    private func keyRow(label: String, key: String, value: String, isBuiltIn: Bool) -> some View {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? "—" : trimmed

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(label)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(displayValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                Text("{{\(key)}}")
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if isBuiltIn {
                Image(systemName: "bolt.circle")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            selectedKey = key
            dismiss()
        }
        .contextMenu {
            Button("Select") {
                selectedKey = key
                dismiss()
            }
            Button("Copy {{key}}") {
                UIPasteboard.general.string = "{{\(key)}}"
            }
            Button("Copy key") {
                UIPasteboard.general.string = key
            }
        }
        .accessibilityLabel(label)
        .accessibilityValue(displayValue)
    }

    private func displayName(for key: String) -> String {
        switch key {
        case "__time": return "Time"
        case "__today": return "Today"
        case "__weekday": return "Weekday"
        case "__now": return "Now (ISO8601)"
        case "__now_unix": return "Now (unix)"
        case "__steps_today": return "Steps today"
        case "__steps_goal_today": return "Steps goal today"
        case "__steps_streak": return "Steps streak"
        case "__activity_steps_today": return "Activity steps today"
        case "__weather_temp": return "Weather temperature"
        case "__weather_condition": return "Weather condition"
        default:
            return key
        }
    }

    private func matchesQuery(_ s: String, q: String) -> Bool {
        if q.isEmpty { return true }
        return s.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().contains(q)
    }
}
