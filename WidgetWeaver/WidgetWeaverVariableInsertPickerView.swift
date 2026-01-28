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
        case all = "All"
        case builtIns = "Built-ins"
        case custom = "Custom"

        var id: String { rawValue }

        static var proScopes: [Scope] { [.all, .builtIns, .custom] }
        static var freeScopes: [Scope] { [.builtIns] }
    }

    let isProUnlocked: Bool
    let customVariables: [String: String]
    let onInsert: (String) -> Void

    @Environment(\.dismiss) private var dismiss

    @AppStorage("variables.insert.scope") private var scopeRaw: String = Scope.all.rawValue
    @State private var searchText: String = ""

    @AppStorage("variables.builtins.showAdvanced") private var showAdvancedKeys: Bool = false
    @AppStorage("variables.insert.keepOpenAfterInsert") private var keepOpenAfterInsert: Bool = false

    @AppStorage("variables.insert.pinnedSnippets.json") private var pinnedSnippetsJSON: String = ""
    @AppStorage("variables.insert.recentSnippets.json") private var recentSnippetsJSON: String = ""

    @State private var showClearPinnedConfirmation: Bool = false
    @State private var showClearRecentsConfirmation: Bool = false

    var body: some View {
        let scope = effectiveScope
        let values = mergedValues
        let searchIsActive = !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

        return List {
            if isProUnlocked {
                Section {
                    Picker("Source", selection: scopeBinding) {
                        ForEach(Scope.proScopes) { scope in
                            Text(scope.rawValue).tag(scope)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            if !searchIsActive {
                historySections(scope: scope, values: values)
            }

            optionsSection(scope: scope)

            if scope == .builtIns || !isProUnlocked || scope == .all {
                builtInsBody
            }

            if scope == .custom || scope == .all {
                customBody
            }

            toolsSection
        }
        .navigationTitle("Insert variable")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Close") { dismiss() }
            }
        }
        .confirmationDialog(
            "Clear pinned snippets?",
            isPresented: $showClearPinnedConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Pinned", role: .destructive) {
                pinnedSnippetsJSON = ""
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This removes pinned snippets on this device.")
        }
        .confirmationDialog(
            "Clear recent inserts?",
            isPresented: $showClearRecentsConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Recents", role: .destructive) {
                recentSnippetsJSON = ""
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This clears the recent insert history on this device.")
        }
        .onAppear {
            if !isProUnlocked {
                scopeRaw = Scope.builtIns.rawValue
            } else if Scope(rawValue: scopeRaw) == nil {
                scopeRaw = Scope.all.rawValue
            }
        }
    }

    private var effectiveScope: Scope {
        if !isProUnlocked { return .builtIns }
        return Scope(rawValue: scopeRaw) ?? .all
    }

    private var scopeBinding: Binding<Scope> {
        Binding(
            get: { effectiveScope },
            set: { newValue in
                scopeRaw = newValue.rawValue
            }
        )
    }

    private var mergedValues: [String: String] {
        var out = resolvedBuiltInValues
        for (k, v) in customVariables {
            out[k] = v
        }
        return out
    }

    // MARK: - Options

    private func optionsSection(scope: Scope) -> some View {
        Section {
            Toggle("Keep open after insert", isOn: $keepOpenAfterInsert)

            if scope != .custom {
                Toggle("Show advanced keys", isOn: $showAdvancedKeys)
            }
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("When enabled, the picker stays open after inserting a snippet.")
                if scope != .custom {
                    Text("Search always includes advanced keys.")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    // MARK: - History

    private enum SnippetKind {
        case builtIn
        case custom
        case other
    }

    private func historySections(scope: Scope, values: [String: String]) -> some View {
        let pinned = visiblePinnedSnippets(scope: scope)
        let recents = visibleRecentSnippets(scope: scope)

        return Group {
            if !pinned.isEmpty {
                Section("Pinned") {
                    ForEach(pinned, id: \.self) { snippet in
                        historyRow(
                            snippet: snippet,
                            values: values,
                            showsPinnedIndicator: false,
                            pinAvailability: .unpin
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                            Button(role: .destructive) {
                                unpinSnippet(snippet)
                            } label: {
                                Label("Unpin", systemImage: "star.slash")
                            }
                        }
                    }
                }
            }

            if !recents.isEmpty {
                Section("Recent") {
                    ForEach(recents, id: \.self) { snippet in
                        historyRow(
                            snippet: snippet,
                            values: values,
                            showsPinnedIndicator: true,
                            pinAvailability: pinnedSnippets.contains(snippet) ? .unpin : .pin
                        )
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if pinnedSnippets.contains(snippet) {
                                Button {
                                    unpinSnippet(snippet)
                                } label: {
                                    Label("Unpin", systemImage: "star.slash")
                                }
                                .tint(.yellow)
                            } else {
                                Button {
                                    pinSnippet(snippet)
                                } label: {
                                    Label("Pin", systemImage: "star")
                                }
                                .tint(.yellow)
                            }

                            Button(role: .destructive) {
                                removeRecentSnippet(snippet)
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private enum PinAvailability {
        case pin
        case unpin
        case unavailable
    }

    private func historyRow(
        snippet: String,
        values: [String: String],
        showsPinnedIndicator: Bool,
        pinAvailability: PinAvailability
    ) -> some View {
        let key = snippetKey(snippet)
        let value: String = {
            guard let key else { return "" }
            return values[key] ?? ""
        }()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? "—" : trimmed
        let isPinned = pinnedSnippets.contains(snippet)

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(snippet)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 0)

            if key != nil {
                Text(displayValue)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            if showsPinnedIndicator, isPinned {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Pinned")
            }

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
            performInsert(snippet)
        }
        .contextMenu {
            Button("Insert") {
                performInsert(snippet)
            }

            Button("Copy") {
                UIPasteboard.general.string = snippet
            }

            switch pinAvailability {
            case .pin:
                Button("Pin") { pinSnippet(snippet) }
            case .unpin:
                Button("Unpin") { unpinSnippet(snippet) }
            case .unavailable:
                EmptyView()
            }

            if recentSnippets.contains(snippet) {
                Button("Remove from Recents") {
                    removeRecentSnippet(snippet)
                }
            }
        }
        .accessibilityLabel(key ?? snippet)
    }

    private func visiblePinnedSnippets(scope: Scope) -> [String] {
        pinnedSnippets.filter { isSnippetVisible($0, in: scope) }
    }

    private func visibleRecentSnippets(scope: Scope) -> [String] {
        recentSnippets.filter { isSnippetVisible($0, in: scope) }
    }

    private func isSnippetVisible(_ snippet: String, in scope: Scope) -> Bool {
        switch scope {
        case .all:
            return true
        case .builtIns:
            return snippetKind(snippet) == .builtIn
        case .custom:
            return snippetKind(snippet) == .custom
        }
    }

    private func snippetKind(_ snippet: String) -> SnippetKind {
        guard let key = snippetKey(snippet) else { return .other }
        if key.hasPrefix("__") { return .builtIn }
        return .custom
    }

    private func snippetKey(_ snippet: String) -> String? {
        guard let start = snippet.range(of: "{{") else { return nil }
        guard let end = snippet.range(of: "}}", range: start.upperBound..<snippet.endIndex) else { return nil }

        let inner = snippet[start.upperBound..<end.lowerBound]
        let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmed.hasPrefix("=") { return nil }

        let keyPart = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
        let key = String(keyPart).trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    private var pinnedSnippets: [String] {
        decodeSnippetList(from: pinnedSnippetsJSON)
    }

    private var recentSnippets: [String] {
        decodeSnippetList(from: recentSnippetsJSON)
    }

    private func pinSnippet(_ snippet: String) {
        let s = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }

        var list = pinnedSnippets
        list.removeAll { $0 == s }
        list.insert(s, at: 0)
        pinnedSnippetsJSON = encodeSnippetList(list.prefix(24).map { $0 })
    }

    private func unpinSnippet(_ snippet: String) {
        let s = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }

        var list = pinnedSnippets
        list.removeAll { $0 == s }
        pinnedSnippetsJSON = encodeSnippetList(list)
    }

    private func recordRecentSnippet(_ snippet: String) {
        let s = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }

        var list = recentSnippets
        list.removeAll { $0 == s }
        list.insert(s, at: 0)
        recentSnippetsJSON = encodeSnippetList(list.prefix(24).map { $0 })
    }

    private func removeRecentSnippet(_ snippet: String) {
        let s = snippet.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return }

        var list = recentSnippets
        list.removeAll { $0 == s }
        recentSnippetsJSON = encodeSnippetList(list)
    }

    private func decodeSnippetList(from json: String) -> [String] {
        let trimmed = json.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return [] }

        guard let data = trimmed.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([String].self, from: data)) ?? []
    }

    private func encodeSnippetList(_ list: [String]) -> String {
        guard let data = try? JSONEncoder().encode(Array(list)) else { return "" }
        return String(data: data, encoding: .utf8) ?? ""
    }

    // MARK: - Content

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
            var out: [BuiltInSnippet] = [
                BuiltInSnippet(key: "snippet.time", label: "Time", snippet: "{{__time}}"),
                BuiltInSnippet(key: "snippet.weekday", label: "Weekday", snippet: "{{__weekday}}"),
                BuiltInSnippet(key: "snippet.today", label: "Today", snippet: "{{__today}}"),
                BuiltInSnippet(key: "snippet.steps", label: "Steps today", snippet: "{{__steps_today|--|number:0}}"),
                BuiltInSnippet(key: "snippet.activity.steps", label: "Activity steps", snippet: "{{__activity_steps_today|--|number:0}}"),
                BuiltInSnippet(key: "snippet.weather.temp", label: "Weather temperature", snippet: "{{__weather_temp|--}}"),
                BuiltInSnippet(key: "snippet.weather.hilo", label: "Weather hi/lo", snippet: "{{__weather_hi|--}} / {{__weather_lo|--}}"),
            ]

            if FeatureFlags.smartPhotoMemoriesEnabled {
                out.append(
                    BuiltInSnippet(
                        key: "snippet.smartphoto.year",
                        label: "Year (Smart Photos)",
                        snippet: "{{__smartphoto_year}}"
                    )
                )
            }

            return out
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
        let isPinned = pinnedSnippets.contains(snippet)

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            Text(snippet)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            if isPinned {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Pinned")
            }

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
            performInsert(snippet)
        }
        .contextMenu {
            Button("Insert") {
                performInsert(snippet)
            }
            Button("Copy") {
                UIPasteboard.general.string = snippet
            }
            if isPinned {
                Button("Unpin") { unpinSnippet(snippet) }
            } else {
                Button("Pin") { pinSnippet(snippet) }
            }
        }
    }

    private func builtInRow(key: String, value: String) -> some View {
        let snippet = "{{\(key)}}"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? "—" : trimmed
        let isPinned = pinnedSnippets.contains(snippet)

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

            if isPinned {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Pinned")
            }

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
            performInsert(snippet)
        }
        .contextMenu {
            Button("Insert") {
                performInsert(snippet)
            }
            Button("Insert with fallback") {
                performInsert("{{\(key)|--}}")
            }
            Button("Copy template") {
                UIPasteboard.general.string = snippet
            }
            Button("Copy key") {
                UIPasteboard.general.string = key
            }
            if isPinned {
                Button("Unpin") { unpinSnippet(snippet) }
            } else {
                Button("Pin") { pinSnippet(snippet) }
            }
        }
    }

    private func customRow(key: String, value: String) -> some View {
        let snippet = "{{\(key)}}"
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? "—" : trimmed
        let isPinned = pinnedSnippets.contains(snippet)

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

            if isPinned {
                Image(systemName: "star.fill")
                    .foregroundStyle(.yellow)
                    .accessibilityLabel("Pinned")
            }

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
            performInsert(snippet)
        }
        .contextMenu {
            Button("Insert") {
                performInsert(snippet)
            }
            Button("Insert with fallback") {
                performInsert("{{\(key)|--}}")
            }
            Button("Copy template") {
                UIPasteboard.general.string = snippet
            }
            Button("Copy key") {
                UIPasteboard.general.string = key
            }
            if isPinned {
                Button("Unpin") { unpinSnippet(snippet) }
            } else {
                Button("Pin") { pinSnippet(snippet) }
            }
        }
    }

    // MARK: - Insert

    private func performInsert(_ snippet: String) {
        recordRecentSnippet(snippet)
        onInsert(snippet)
        if !keepOpenAfterInsert {
            dismiss()
        }
    }

    // MARK: - Tools

    private var toolsSection: some View {
        let hasPinned = !pinnedSnippets.isEmpty
        let hasRecents = !recentSnippets.isEmpty

        return Group {
            if hasPinned || hasRecents {
                Section("Tools") {
                    if hasPinned {
                        Button(role: .destructive) {
                            showClearPinnedConfirmation = true
                        } label: {
                            Label("Clear pinned snippets", systemImage: "star.slash")
                        }
                    }

                    if hasRecents {
                        Button(role: .destructive) {
                            showClearRecentsConfirmation = true
                        } label: {
                            Label("Clear recent inserts", systemImage: "clock.arrow.circlepath")
                        }
                    }
                }
            }
        }
    }
}
