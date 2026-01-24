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

                NavigationLink {
                    WidgetWeaverVariableReferenceView(tryItInput: $tryItInput)
                } label: {
                    Label("Syntax & filters", systemImage: "text.book.closed")
                }
            } footer: {
                Text("Tap a row to insert {{key}} into Try it. Searching always includes advanced keys.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ForEach(sections) { section in
                let filtered = section.keys
                    .filter { includeAdvanced || !isAdvancedKey($0) }
                    .filter { q.isEmpty || $0.lowercased().contains(q) }

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

    private struct BuiltInSection: Identifiable, Hashable {
        let id: String
        let title: String
        let keys: [String]
    }

    private var resolvedValues: [String: String] {
        var out = WidgetWeaverVariableTemplate.builtInVariables(now: WidgetWeaverRenderClock.now)
        out.merge(WidgetWeaverWeatherStore.shared.variablesDictionary(now: WidgetWeaverRenderClock.now), uniquingKeysWith: { _, new in new })
        out.merge(WidgetWeaverStepsStore.shared.variablesDictionary(now: WidgetWeaverRenderClock.now), uniquingKeysWith: { _, new in new })
        out.merge(WidgetWeaverActivityStore.shared.variablesDictionary(now: WidgetWeaverRenderClock.now), uniquingKeysWith: { _, new in new })
        return out
    }

    private func isAdvancedKey(_ key: String) -> Bool {
        if key.hasPrefix("__weather_") { return true }
        if key.hasPrefix("__steps_") { return true }
        if key.hasPrefix("__activity_") { return true }
        if key == "__now_unix" { return true }
        return false
    }

    private func builtInRow(key: String, value: String) -> some View {
        let snippet = "{{\(key)}}"

        return HStack(alignment: .firstTextBaseline, spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(key)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                if value.isEmpty {
                    Text("—")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Text(value)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }

                Text(snippet)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

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

struct WidgetWeaverVariableReferenceView: View {
    @Binding var tryItInput: String

    @State private var searchText: String = ""

    var body: some View {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let matches = referenceItems.filter { item in
            if q.isEmpty { return true }
            if item.title.lowercased().contains(q) { return true }
            if item.snippet.lowercased().contains(q) { return true }
            if let detail = item.detail, detail.lowercased().contains(q) { return true }
            return false
        }

        let groups = groupedItems(from: matches)

        return List {
            Section {
                Text("Tap a row to insert the snippet into Try it. Use the copy button or long-press for more options.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            ForEach(groups) { group in
                Section(group.title) {
                    ForEach(group.items) { item in
                        referenceRow(item: item)
                    }
                }
            }
        }
        .navigationTitle("Syntax & filters")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
    }

    private struct ReferenceItem: Identifiable, Hashable {
        let id: String
        let section: String
        let title: String
        let detail: String?
        let snippet: String

        init(section: String, title: String, detail: String? = nil, snippet: String) {
            self.section = section
            self.title = title
            self.detail = detail
            self.snippet = snippet
            self.id = section + "|" + title + "|" + snippet
        }
    }

    private struct ReferenceGroup: Identifiable, Hashable {
        let id: String
        let title: String
        let items: [ReferenceItem]

        init(title: String, items: [ReferenceItem]) {
            self.title = title
            self.items = items
            self.id = title
        }
    }

    private var referenceItems: [ReferenceItem] {
        [
            ReferenceItem(
                section: "Basics",
                title: "Key",
                detail: "Replaces the token with a stored variable or built-in key value.",
                snippet: "{{streak}}"
            ),
            ReferenceItem(
                section: "Basics",
                title: "Fallback",
                detail: "Uses the fallback when the key is missing or empty.",
                snippet: "{{streak|0}}"
            ),
            ReferenceItem(
                section: "Basics",
                title: "Fallback + filters (use ||)",
                detail: "Use || when the fallback contains | characters, or to make the pipeline unambiguous.",
                snippet: "{{name|Friend||title}}"
            ),

            ReferenceItem(
                section: "Text filters",
                title: "Upper / lower / title",
                detail: "Simple casing filters.",
                snippet: "{{name|Friend||upper}}"
            ),
            ReferenceItem(
                section: "Text filters",
                title: "Trim + pad",
                detail: "Trims whitespace, then left-pads with zeroes.",
                snippet: "{{code|0||trim|pad:4}}"
            ),
            ReferenceItem(
                section: "Text filters",
                title: "Prefix / suffix",
                detail: "Adds extra text around a value.",
                snippet: "{{count|0|suffix: items}}"
            ),

            ReferenceItem(
                section: "Numbers",
                title: "Number formatting",
                detail: "Locale-aware number formatting with fixed decimals.",
                snippet: "{{amount|0|number:0}}"
            ),
            ReferenceItem(
                section: "Numbers",
                title: "Percent",
                detail: "0–1 treated as a fraction (0.42 → 42%).",
                snippet: "{{progress|0|percent:0}}"
            ),
            ReferenceItem(
                section: "Numbers",
                title: "Currency",
                detail: "Optional currency code (for example EUR).",
                snippet: "{{price|0|currency:EUR}}"
            ),
            ReferenceItem(
                section: "Numbers",
                title: "Clamp",
                detail: "Constrains the value into a range.",
                snippet: "{{score|0|clamp:0:100}}"
            ),

            ReferenceItem(
                section: "Dates",
                title: "Format (date:FORMAT)",
                detail: "Accepts ISO8601, unix seconds/milliseconds, and common local formats.",
                snippet: "{{__now||date:EEE d MMM}}"
            ),
            ReferenceItem(
                section: "Dates",
                title: "Relative",
                detail: "Example output: “2 hours ago”.",
                snippet: "{{last_done|Never|relative}}"
            ),
            ReferenceItem(
                section: "Dates",
                title: "Days until",
                detail: "Ceiling of days until a target date/time.",
                snippet: "{{deadline|—|daysuntil}}"
            ),
            ReferenceItem(
                section: "Dates",
                title: "Minutes since",
                detail: "Ceiling of minutes since a target date/time.",
                snippet: "{{last_done|0|sinceminutes}}"
            ),

            ReferenceItem(
                section: "Progress bar",
                title: "Bar (bar:WIDTH)",
                detail: "0–1 treated as a fraction; values >1 treated as percentages.",
                snippet: "{{progress|0|bar:10}}"
            ),
            ReferenceItem(
                section: "Plural",
                title: "Plural (plural:ONE:MANY)",
                detail: "Chooses based on the numeric value (absolute value equals 1 uses the singular form).",
                snippet: "{{count|0|plural:item:items}}"
            ),

            ReferenceItem(
                section: "Inline maths",
                title: "Expression",
                detail: "Identifiers resolve as variable keys (underscores map to spaces). Missing values become 0.",
                snippet: "{{=done/total*100|0|number:0}}%"
            ),
            ReferenceItem(
                section: "Inline maths",
                title: "Functions",
                detail: "Common helpers include min/max/clamp/abs/floor/ceil/round/pow/sqrt/log/exp.",
                snippet: "{{=max(0, streak-1)|0}}"
            ),
            ReferenceItem(
                section: "Inline maths",
                title: "now() in maths",
                detail: "Returns unix seconds for the render-time now.",
                snippet: "{{=now()|0}}"
            ),
        ]
    }

    private func groupedItems(from items: [ReferenceItem]) -> [ReferenceGroup] {
        let order: [String] = [
            "Basics",
            "Text filters",
            "Numbers",
            "Dates",
            "Progress bar",
            "Plural",
            "Inline maths",
        ]

        var dict: [String: [ReferenceItem]] = [:]
        for item in items {
            dict[item.section, default: []].append(item)
        }

        var groups: [ReferenceGroup] = []
        for section in order {
            let sectionItems = dict[section] ?? []
            if !sectionItems.isEmpty {
                groups.append(ReferenceGroup(title: section, items: sectionItems))
            }
        }

        return groups
    }

    private func referenceRow(item: ReferenceItem) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)

                Text(item.snippet)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                if let detail = item.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)

            Button {
                UIPasteboard.general.string = item.snippet
            } label: {
                Image(systemName: "doc.on.doc")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Copy snippet")
        }
        .contentShape(Rectangle())
        .onTapGesture {
            insertSnippet(item.snippet)
        }
        .contextMenu {
            Button("Insert") {
                insertSnippet(item.snippet)
            }
            Button("Copy") {
                UIPasteboard.general.string = item.snippet
            }
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
