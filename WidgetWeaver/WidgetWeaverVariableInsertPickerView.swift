//
//  WidgetWeaverVariableInsertPickerView.swift
//  WidgetWeaver
//
//  Created by . . on 1/24/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverVariableInsertPickerView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case builtIns = "Built-ins"
        case custom = "Custom"

        var id: String { rawValue }
    }

    let isProUnlocked: Bool
    let customVariables: [String: String]
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var scope: Scope = .builtIns
    @State private var searchText: String = ""

    @AppStorage("variables.builtins.showAdvanced") private var showAdvancedKeys: Bool = false

    var body: some View {
        List {
            if isProUnlocked {
                Section {
                    Picker("Source", selection: $scope) {
                        ForEach(Scope.allCases) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if scope == .builtIns || !isProUnlocked {
                builtInsBody
            } else {
                customBody
            }
        }
        .navigationTitle("Insert variable")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
        .onAppear {
            if !isProUnlocked {
                scope = .builtIns
            }
        }
    }

    private var builtInsBody: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let includeAdvanced = showAdvancedKeys || !q.isEmpty
        let values = resolvedBuiltInValues

        let snippetMatches = builtInSnippets.filter { item in
            if q.isEmpty { return true }
            return item.key.lowercased().contains(q)
                || item.label.lowercased().contains(q)
                || item.snippet.lowercased().contains(q)
        }

        let sections: [BuiltInSection] = [
            BuiltInSection(id: "time", title: "Time", keys: ["__now", "__now_unix", "__today", "__time", "__weekday"]),
            BuiltInSection(id: "weather", title: "Weather", keys: values.keys.filter { $0.hasPrefix("__weather_") }.sorted()),
            BuiltInSection(id: "steps", title: "Steps", keys: values.keys.filter { $0.hasPrefix("__steps_") }.sorted()),
            BuiltInSection(id: "activity", title: "Activity", keys: values.keys.filter { $0.hasPrefix("__activity_") }.sorted()),
        ]

        return Group {
            Section {
                Toggle("Show advanced keys", isOn: $showAdvancedKeys)
            } footer: {
                Text("Search always includes advanced keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !snippetMatches.isEmpty {
                Section("Snippets") {
                    ForEach(snippetMatches) { item in
                        snippetRow(label: item.label, snippet: item.snippet)
                    }
                }
            }

            ForEach(sections) { section in
                let filtered = section.keys
                    .filter { includeAdvanced || !isAdvancedKey($0) }
                    .filter { q.isEmpty ? true : $0.lowercased().contains(q) }

                if !filtered.isEmpty {
                    Section(section.title) {
                        ForEach(filtered, id: \.self) { key in
                            builtInRow(key: key, value: values[key] ?? "")
                        }
                    }
                }
            }

            if !isProUnlocked {
                Section {
                    Label("Custom variables require WidgetWeaver Pro.", systemImage: "lock.fill")
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var customBody: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let keys = customVariables.keys.sorted().filter { key in
            if q.isEmpty { return true }
            return key.lowercased().contains(q) || (customVariables[key] ?? "").lowercased().contains(q)
        }

        return Group {
            if keys.isEmpty {
                Section {
                    Text(q.isEmpty ? "No variables yet." : "No matches.")
                        .foregroundStyle(.secondary)
                }
            } else {
                Section("Variables (\(customVariables.count))") {
                    ForEach(keys, id: \.self) { key in
                        customRow(key: key, value: customVariables[key] ?? "")
                    }
                }
            }

            Section {
                Text("Tap to insert {{key}} into the active text field.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private struct BuiltInSection: Identifiable {
        let id: String
        let title: String
        let keys: [String]
    }

    private struct BuiltInSnippet: Identifiable, Hashable {
        let id: String
        let key: String
        let label: String
        let snippet: String

        init(key: String, label: String, snippet: String) {
            self.key = key
            self.label = label
            self.snippet = snippet
            self.id = key
        }
    }

    private var builtInSnippets: [BuiltInSnippet] {
        [
            BuiltInSnippet(key: "snippet.time", label: "Time", snippet: "{{__time}}"),
            BuiltInSnippet(key: "snippet.weekday", label: "Weekday", snippet: "{{__weekday}}"),
            BuiltInSnippet(key: "snippet.today", label: "Today", snippet: "{{__today}}"),
            BuiltInSnippet(key: "snippet.steps", label: "Steps today", snippet: "{{__steps_today|--|number:0}}"),
            BuiltInSnippet(key: "snippet.activity.steps", label: "Activity steps", snippet: "{{__activity_steps_today|--|number:0}}"),
            BuiltInSnippet(key: "snippet.weather.temp", label: "Weather temperature", snippet: "{{__weather_temp|--}}"),
        ]
    }

    private var resolvedBuiltInValues: [String: String] {
        let now = WidgetWeaverRenderClock.now

        var vars = WidgetWeaverVariableTemplate.builtInVariables(now: now)
        for (k, v) in WidgetWeaverWeatherStore.shared.variablesDictionary(now: now) { vars[k] = v }
        for (k, v) in WidgetWeaverStepsStore.shared.variablesDictionary(now: now) { vars[k] = v }
        for (k, v) in WidgetWeaverActivityStore.shared.variablesDictionary(now: now) { vars[k] = v }

        return vars
    }

    private func isAdvancedKey(_ key: String) -> Bool {
        let k = key.lowercased()

        if k.contains("_exact") { return true }
        if k.contains("_fraction") { return true }
        if k.hasSuffix("_iso") { return true }
        if k.hasSuffix("_unix") { return true }
        if k.hasSuffix("_symbol") { return true }
        if k.contains("_start") || k.contains("_end") || k.contains("_peak") { return true }
        if k.hasSuffix("_access") { return true }
        if k.hasSuffix("_lat") || k.hasSuffix("_lon") { return true }

        return false
    }

    private func snippetRow(label: String, snippet: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Text(snippet)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                UIPasteboard.general.string = snippet
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy snippet")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onInsert(snippet)
            dismiss()
        }
        .contextMenu {
            Button("Insert") {
                onInsert(snippet)
                dismiss()
            }
            Button("Copy") {
                UIPasteboard.general.string = snippet
            }
        }
    }

    private func builtInRow(key: String, value: String) -> some View {
        let snippet = "{{\(key)}}"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? "—" : trimmed

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(displayValue)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                UIPasteboard.general.string = snippet
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy template")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onInsert(snippet)
            dismiss()
        }
        .contextMenu {
            Button("Insert") {
                onInsert(snippet)
                dismiss()
            }
            Button("Insert with fallback") {
                onInsert("{{\(key)|--}}")
                dismiss()
            }
            Button("Copy template") {
                UIPasteboard.general.string = snippet
            }
            Button("Copy key") {
                UIPasteboard.general.string = key
            }
        }
    }

    private func customRow(key: String, value: String) -> some View {
        let snippet = "{{\(key)}}"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? "—" : trimmed

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            Text(displayValue)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Button {
                UIPasteboard.general.string = snippet
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy template")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            onInsert(snippet)
            dismiss()
        }
        .contextMenu {
            Button("Insert") {
                onInsert(snippet)
                dismiss()
            }
            Button("Insert with fallback") {
                onInsert("{{\(key)|--}}")
                dismiss()
            }
            Button("Copy template") {
                UIPasteboard.general.string = snippet
            }
            Button("Copy key") {
                UIPasteboard.general.string = key
            }
        }
    }
}
