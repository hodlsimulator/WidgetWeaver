//
//  WidgetWeaverBuiltInKeysView.swift
//  WidgetWeaver
//
//  Created by . . on 1/23/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverBuiltInKeysView: View {
    @Binding var tryItInput: String

    @State private var searchText: String = ""
    @AppStorage("variables.builtins.showAdvanced") private var showAdvancedKeys: Bool = false

    var body: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let includeAdvanced = showAdvancedKeys || !q.isEmpty
        let values = resolvedValues

        let sections: [BuiltInSection] = [
            BuiltInSection(id: "time", title: "Time", keys: ["__now", "__now_unix", "__today", "__time", "__weekday"]),
            BuiltInSection(id: "weather", title: "Weather", keys: values.keys.filter { $0.hasPrefix("__weather_") }.sorted()),
            BuiltInSection(id: "steps", title: "Steps", keys: values.keys.filter { $0.hasPrefix("__steps_") }.sorted()),
            BuiltInSection(id: "activity", title: "Activity", keys: values.keys.filter { $0.hasPrefix("__activity_") }.sorted()),
        ]

        return List {
            Section {
                Toggle("Show advanced keys", isOn: $showAdvancedKeys)
            } footer: {
                Text("Tap a row to insert {{key}} into Try it. Searching always includes advanced keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
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
        }
        .navigationTitle("Built-in keys")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
    }

    private struct BuiltInSection: Identifiable {
        let id: String
        let title: String
        let keys: [String]
    }

    private var resolvedValues: [String: String] {
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
            insertSnippet(snippet)
        }
    }

    private func insertSnippet(_ snippet: String) {
        let trimmed = tryItInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tryItInput = snippet
            return
        }

        if let last = tryItInput.last, last == "\n" || last == " " {
            tryItInput += snippet
        } else {
            tryItInput += " " + snippet
        }
    }
}
