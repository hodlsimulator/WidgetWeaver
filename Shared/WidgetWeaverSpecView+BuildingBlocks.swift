//
//  WidgetWeaverSpecView+BuildingBlocks.swift
//  WidgetWeaver
//
//  Created by . . on 1/16/26.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit
import AppIntents

extension WidgetWeaverSpecView {
    // MARK: - Building Blocks

    func headerRow(spec: WidgetSpec, style: StyleSpec, accent: Color) -> some View {
        HStack(alignment: .firstTextBaseline) {
            if !spec.name.isEmpty {
                Text(spec.name)
                    .font(style.nameTextStyle.font(fallback: .caption))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)
        }
    }

    func contentStackClassic(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let parsedList: ParsedList? = {
            guard let secondaryText = spec.secondaryText, !secondaryText.isEmpty else { return nil }
            return Self.parseListIfPossible(secondaryText)
        }()

        return VStack(alignment: layout.alignment.alignment, spacing: 6) {
            if !spec.primaryText.isEmpty {
                if let parsedList, parsedList.isChecklist {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(spec.primaryText)
                            .font(style.primaryTextStyle.font(fallback: .title3))
                            .foregroundStyle(.primary)
                            .lineLimit(family == .systemSmall ? layout.primaryLineLimitSmall : layout.primaryLineLimit)

                        Spacer(minLength: 0)

                        listProgressPill(done: parsedList.doneCount, total: parsedList.totalCount, accent: accent)
                    }
                } else {
                    Text(spec.primaryText)
                        .font(style.primaryTextStyle.font(fallback: .title3))
                        .foregroundStyle(.primary)
                        .lineLimit(family == .systemSmall ? layout.primaryLineLimitSmall : layout.primaryLineLimit)
                }
            }

            if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                if let parsedList {
                    listItemsView(parsed: parsedList, style: style, accent: accent)
                } else {
                    Text(secondaryText)
                        .font(style.secondaryTextStyle.font(fallback: .caption2))
                        .foregroundStyle(.secondary)
                        .lineLimit(family == .systemSmall ? layout.secondaryLineLimitSmall : layout.secondaryLineLimit)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: Alignment(horizontal: layout.alignment.alignment, vertical: .top)
        )
    }

    func contentStackHero(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let parsedList: ParsedList? = {
            guard let secondaryText = spec.secondaryText, !secondaryText.isEmpty else { return nil }
            return Self.parseListIfPossible(secondaryText)
        }()

        return VStack(alignment: layout.alignment.alignment, spacing: 6) {
            if !spec.primaryText.isEmpty {
                if let parsedList, parsedList.isChecklist {
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(spec.primaryText)
                            .font(style.primaryTextStyle.font(fallback: .title3))
                            .foregroundStyle(.primary)
                            .lineLimit(family == .systemSmall ? layout.primaryLineLimitSmall : layout.primaryLineLimit)

                        Spacer(minLength: 0)

                        listProgressPill(done: parsedList.doneCount, total: parsedList.totalCount, accent: accent)
                    }
                } else {
                    Text(spec.primaryText)
                        .font(style.primaryTextStyle.font(fallback: .title3))
                        .foregroundStyle(.primary)
                        .lineLimit(family == .systemSmall ? layout.primaryLineLimitSmall : layout.primaryLineLimit)
                }
            }

            if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                if let parsedList {
                    listItemsView(parsed: parsedList, style: style, accent: accent)
                } else {
                    Text(secondaryText)
                        .font(style.secondaryTextStyle.font)
                        .foregroundStyle(.secondary)
                        .lineLimit(family == .systemSmall ? layout.secondaryLineLimitSmall : layout.secondaryLineLimit)
                }
            }
        }
        .frame(
            maxWidth: .infinity,
            alignment: Alignment(horizontal: layout.alignment.alignment, vertical: .top)
        )
    }

    // MARK: - List rendering (Classic/Hero)

    private struct ListItem: Identifiable, Hashable {
        let id: Int
        let text: String
        let isDone: Bool
    }

    private struct ParsedList {
        let items: [ListItem]
        let isChecklist: Bool
        let doneCount: Int

        var totalCount: Int { items.count }
    }

    private func listItemsView(parsed: ParsedList, style: StyleSpec, accent: Color) -> some View {
        let maxVisible = listMaxVisibleItems(for: family)
        let visible = Array(parsed.items.prefix(maxVisible))
        let remaining = max(0, parsed.items.count - visible.count)

        return VStack(alignment: .leading, spacing: listRowSpacing(for: family)) {
            ForEach(visible) { item in
                listItemRow(item: item, style: style, accent: accent, isChecklist: parsed.isChecklist)
            }

            if remaining > 0 {
                listMoreRow(remaining: remaining, style: style)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func listItemRow(item: ListItem, style: StyleSpec, accent: Color, isChecklist: Bool) -> some View {
        let iconName: String = {
            if isChecklist {
                return item.isDone ? "checkmark.circle.fill" : "circle"
            }
            return "circle.fill"
        }()

        let iconOpacity: Double = {
            if isChecklist {
                return item.isDone ? 0.95 : 0.55
            }
            return 0.55
        }()

        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            Image(systemName: iconName)
                .font(.system(size: listIconPointSize(for: family), weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(accent.opacity(iconOpacity))
                .accessibilityHidden(true)

            Text(item.text)
                .font(style.secondaryTextStyle.font(fallback: .caption2))
                .foregroundStyle((isChecklist && item.isDone) ? .secondary : .primary)
                .strikethrough(isChecklist && item.isDone, color: .secondary.opacity(0.8))
                .lineLimit(1)
                .minimumScaleFactor(0.78)

            Spacer(minLength: 0)
        }
    }

    private func listMoreRow(remaining: Int, style: StyleSpec) -> some View {
        Text("+\(remaining) more")
            .font(style.secondaryTextStyle.font(fallback: .caption2).weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
    }

    private func listProgressPill(done: Int, total: Int, accent: Color) -> some View {
        let shape = Capsule(style: .continuous)
        return Text("\(done)/\(total)")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.secondary)
            .monospacedDigit()
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background { shape.fill(accent.opacity(0.16)) }
            .overlay { shape.strokeBorder(accent.opacity(0.28), lineWidth: 1) }
            .accessibilityLabel("\(done) of \(total) complete")
    }

    private func listMaxVisibleItems(for family: WidgetFamily) -> Int {
        switch family {
        case .systemSmall:
            return 3
        case .systemMedium:
            return 6
        case .systemLarge:
            return 10
        case .systemExtraLarge:
            return 12
        default:
            return 3
        }
    }

    private func listRowSpacing(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 7
        default:
            return 8
        }
    }

    private func listIconPointSize(for family: WidgetFamily) -> CGFloat {
        switch family {
        case .systemSmall:
            return 12
        default:
            return 13
        }
    }

    private static func parseListIfPossible(_ rawText: String) -> ParsedList? {
        let lines = rawText
            .split(whereSeparator: \.isNewline)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard lines.count >= 2 else { return nil }

        let prefixCount = lines.filter { hasListPrefix($0) }.count
        guard prefixCount >= 2 else { return nil }

        var items: [ListItem] = []
        items.reserveCapacity(lines.count)

        var usesCheckboxSyntax = false
        var doneCount = 0

        for (idx, line) in lines.enumerated() {
            guard let parsed = parseListLine(line) else { continue }
            items.append(ListItem(id: idx, text: parsed.text, isDone: parsed.isDone))
            usesCheckboxSyntax = usesCheckboxSyntax || parsed.usesCheckboxSyntax
            if parsed.isDone { doneCount += 1 }
        }

        guard items.count >= 2 else { return nil }

        let isChecklist = usesCheckboxSyntax || doneCount > 0
        return ParsedList(items: items, isChecklist: isChecklist, doneCount: doneCount)
    }

    private static func parseListLine(_ line: String) -> (text: String, isDone: Bool, usesCheckboxSyntax: Bool)? {
        var s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return nil }

        var isDone = false
        var usesCheckboxSyntax = false

        func stripLeadingWhitespace() {
            s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        }

        func stripPrefix(_ prefix: String) -> Bool {
            guard s.hasPrefix(prefix) else { return false }
            s = String(s.dropFirst(prefix.count))
            stripLeadingWhitespace()
            return true
        }

        func stripPrefixCaseInsensitive(_ prefixLower: String) -> Bool {
            let lower = s.lowercased()
            guard lower.hasPrefix(prefixLower) else { return false }
            s = String(s.dropFirst(prefixLower.count))
            stripLeadingWhitespace()
            return true
        }

        // Markdown checkbox: "- [ ] item" / "- [x] item"
        if stripPrefixCaseInsensitive("- [x]") || stripPrefixCaseInsensitive("* [x]") || stripPrefixCaseInsensitive("[x]") {
            usesCheckboxSyntax = true
            isDone = true
        } else if stripPrefixCaseInsensitive("- [ ]") || stripPrefixCaseInsensitive("* [ ]") || stripPrefixCaseInsensitive("[ ]") {
            usesCheckboxSyntax = true
            isDone = false
        } else if stripPrefixCaseInsensitive("x ") {
            isDone = true
        } else if stripPrefix("✅") || stripPrefix("☑") || stripPrefix("✔") || stripPrefix("✓") {
            isDone = true
        } else if stripPrefix("☐") {
            isDone = false
        }

        // Numbered list prefix: "1. " / "1) "
        if let afterNumber = stripNumberedPrefix(s) {
            s = afterNumber
            stripLeadingWhitespace()
        }

        // Bullet prefixes.
        let bulletPrefixes: [String] = ["•", "-", "*", "–", "—", "·"]
        for b in bulletPrefixes {
            if stripPrefix(b) { break }
        }

        stripLeadingWhitespace()
        guard !s.isEmpty else { return nil }
        return (s, isDone, usesCheckboxSyntax)
    }

    private static func hasListPrefix(_ line: String) -> Bool {
        let s = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !s.isEmpty else { return false }

        let lower = s.lowercased()

        if lower.hasPrefix("- [ ]") || lower.hasPrefix("* [ ]") || lower.hasPrefix("[ ]") { return true }
        if lower.hasPrefix("- [x]") || lower.hasPrefix("* [x]") || lower.hasPrefix("[x]") { return true }

        if lower.hasPrefix("x ") { return true }

        if s.hasPrefix("•") || s.hasPrefix("-") || s.hasPrefix("*") || s.hasPrefix("–") || s.hasPrefix("—") || s.hasPrefix("·") { return true }
        if s.hasPrefix("☐") || s.hasPrefix("☑") || s.hasPrefix("✅") || s.hasPrefix("✓") || s.hasPrefix("✔") { return true }

        if stripNumberedPrefix(s) != nil { return true }

        return false
    }

    private static func stripNumberedPrefix(_ s: String) -> String? {
        var idx = s.startIndex
        var sawDigit = false

        while idx < s.endIndex, s[idx].isNumber {
            sawDigit = true
            idx = s.index(after: idx)
        }

        guard sawDigit, idx < s.endIndex else { return nil }
        let marker = s[idx]
        guard marker == "." || marker == ")" else { return nil }

        idx = s.index(after: idx)
        guard idx < s.endIndex else { return nil }
        guard s[idx].isWhitespace else { return nil }

        while idx < s.endIndex, s[idx].isWhitespace {
            idx = s.index(after: idx)
        }

        return idx < s.endIndex ? String(s[idx...]) : ""
    }

    func imageRowClassic(symbol: WidgetSymbol, style: StyleSpec, accent: Color) -> some View {
        HStack {
            Spacer(minLength: 0)

            Image(systemName: symbol.name)
                .font(.system(size: style.symbolSize))
                .foregroundStyle(accent)
                .opacity(0.85)
        }
    }

    func accentBar(accent: Color, style: StyleSpec) -> some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(accent)
            .frame(height: 5)
            .opacity(0.9)
    }

}
