//
//  WidgetWeaverVariableSnippetChipsRow.swift
//  WidgetWeaver
//
//  Created by . . on 1/26/26.
//

import SwiftUI
import UIKit

/// A compact horizontal row of tappable snippet "chips" for quickly inserting variable templates.
///
/// The row combines:
/// - Pinned snippets (shared with the Insert Variable picker)
/// - Recent inserts (shared with the Insert Variable picker)
/// - A caller-provided default snippet list (always appended after history)
///
/// Pinned/Recent storage is device-local and backed by AppStorage.
struct WidgetWeaverVariableSnippetChipsRow: View {
    let isProUnlocked: Bool
    let defaults: [String]
    let onInsert: (String) -> Void
    let onOpenPicker: (() -> Void)?

    @AppStorage("variables.insert.pinnedSnippets.json") private var pinnedSnippetsJSON: String = ""
    @AppStorage("variables.insert.recentSnippets.json") private var recentSnippetsJSON: String = ""

    init(
        isProUnlocked: Bool,
        defaults: [String],
        onInsert: @escaping (String) -> Void,
        onOpenPicker: (() -> Void)? = nil
    ) {
        self.isProUnlocked = isProUnlocked
        self.defaults = defaults
        self.onInsert = onInsert
        self.onOpenPicker = onOpenPicker
    }

    var body: some View {
        let pinned = visiblePinnedSnippets
        let recents = visibleRecentSnippets
        let snippets = mergedSnippets(pinned: pinned, recents: recents, defaults: defaults)

        return Group {
            if snippets.isEmpty && onOpenPicker == nil {
                EmptyView()
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(snippets, id: \.self) { snippet in
                            snippetChip(snippet: snippet, isPinned: pinned.contains(snippet))
                        }

                        if let onOpenPicker {
                            Button {
                                onOpenPicker()
                            } label: {
                                Label("More…", systemImage: "curlybraces.square")
                                    .font(.caption2)
                                    .foregroundStyle(.primary)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Insert variable…")
                        }
                    }
                    .padding(.vertical, 2)
                }
                .accessibilityIdentifier("VariableSnippetChipsRow")
            }
        }
    }

    // MARK: - Chip

    private func snippetChip(snippet: String, isPinned: Bool) -> some View {
        Button {
            performInsert(snippet)
        } label: {
            HStack(spacing: 6) {
                if isPinned {
                    Image(systemName: "star.fill")
                        .font(.caption2)
                        .foregroundStyle(.yellow)
                        .accessibilityHidden(true)
                }

                Text(snippet)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 10)
            .background(.thinMaterial, in: Capsule())
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button("Insert") {
                performInsert(snippet)
            }

            Button("Copy snippet") {
                UIPasteboard.general.string = snippet
            }

            if let key = snippetKey(snippet) {
                Button("Copy key") {
                    UIPasteboard.general.string = key
                }
            }

            if isPinned {
                Button("Unpin") { unpinSnippet(snippet) }
            } else {
                Button("Pin") { pinSnippet(snippet) }
            }
        }
        .accessibilityLabel(isPinned ? "Pinned snippet" : "Snippet")
        .accessibilityValue(snippet)
    }

    // MARK: - Merge / visibility

    private var visiblePinnedSnippets: [String] {
        pinnedSnippets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { isSnippetVisible($0) }
    }

    private var visibleRecentSnippets: [String] {
        recentSnippets
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { isSnippetVisible($0) }
    }

    private func mergedSnippets(pinned: [String], recents: [String], defaults: [String]) -> [String] {
        var seen: Set<String> = []
        var out: [String] = []
        out.reserveCapacity(pinned.count + recents.count + defaults.count)

        func appendList(_ list: [String]) {
            for raw in list {
                let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !s.isEmpty else { continue }
                if seen.insert(s).inserted {
                    out.append(s)
                }
            }
        }

        appendList(pinned)
        appendList(recents)
        appendList(defaults)

        return out
    }

    // MARK: - Insert + history

    private func performInsert(_ snippet: String) {
        recordRecentSnippet(snippet)
        onInsert(snippet)
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
        pinnedSnippetsJSON = encodeSnippetList(Array(list.prefix(24)))
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
        recentSnippetsJSON = encodeSnippetList(Array(list.prefix(24)))
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

    // MARK: - Snippet parsing

    private enum SnippetKind {
        case builtIn
        case custom
        case other
    }

    private func isSnippetVisible(_ snippet: String) -> Bool {
        if isProUnlocked { return true }
        return snippetKind(snippet) == .builtIn
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
}
