//
//  WidgetWeaverSpecView.swift
//  WidgetWeaver
//
//  Created by . . on 12/17/25.
//

import Foundation
import SwiftUI
import WidgetKit
import UIKit
import AppIntents

public enum WidgetWeaverRenderContext: String, Codable, Sendable {
    case widget
    case preview
    case simulator
}

public struct WidgetWeaverSpecView: View {
    public let spec: WidgetSpec
    public let family: WidgetFamily
    public let context: WidgetWeaverRenderContext

    @AppStorage(WidgetWeaverWeatherStore.Keys.snapshotData, store: AppGroup.userDefaults)
    private var weatherSnapshotData: Data = Data()

    @AppStorage(WidgetWeaverWeatherStore.Keys.attributionData, store: AppGroup.userDefaults)
    private var weatherAttributionData: Data = Data()

    // Forces a re-render when the saved spec store changes (so Home Screen widgets update).
    @AppStorage("widgetweaver.specs.v1", store: AppGroup.userDefaults)
    private var specsData: Data = Data()

    public init(spec: WidgetSpec, family: WidgetFamily, context: WidgetWeaverRenderContext) {
        self.spec = spec
        self.family = family
        self.context = context
    }

    public var body: some View {
        // Touch AppStorage so WidgetKit redraws when these change.
        let _ = weatherSnapshotData
        let _ = weatherAttributionData
        let _ = specsData

        let baseSpec: WidgetSpec = {
            guard context == .widget else { return spec }
            // Prefer the latest saved version of the same design ID when rendering in WidgetKit.
            // This prevents stale timeline entries from keeping an old design on the Home Screen.
            return WidgetSpecStore.shared.load(id: spec.id) ?? spec
        }()

        let resolved = baseSpec.resolved(for: family).resolvingVariables()
        let style = resolved.style
        let layout = resolved.layout
        let accent = style.accent.swiftUIColor
        let frameAlignment: Alignment = layout.alignment.swiftUIAlignment

        let background = backgroundView(spec: resolved, layout: layout, style: style, accent: accent)

        return VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            switch layout.template {
            case .classic:
                classicTemplate(spec: resolved, layout: layout, style: style, accent: accent)
            case .hero:
                heroTemplate(spec: resolved, layout: layout, style: style, accent: accent)
            case .poster:
                posterTemplate(spec: resolved, layout: layout, style: style, accent: accent)
            case .weather:
                weatherTemplate(spec: resolved, layout: layout, style: style, accent: accent)
            case .nextUpCalendar:
                nextUpCalendarTemplate(spec: resolved, layout: layout, style: style, accent: accent)
            case .reminders:
                remindersTemplatePlaceholder(spec: resolved, layout: layout, style: style, accent: accent)
            }
        }
        .padding(layout.template == .poster || layout.template == .weather ? 0 : style.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: frameAlignment)
        .modifier(
            WidgetWeaverBackgroundModifier(
                family: family,
                context: context,
                background: background
            )
        )
    }

    // MARK: - Templates

    private func classicTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow(spec: spec, style: style, accent: accent)
            contentStackClassic(spec: spec, layout: layout, style: style, accent: accent)

            if let symbol = spec.symbol {
                imageRowClassic(symbol: symbol, style: style, accent: accent)
            }

            actionBarIfNeeded(spec: spec, accent: accent)

            if layout.showsAccentBar {
                accentBar(accent: accent, style: style)
            }
        }
    }

    private func heroTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow(spec: spec, style: style, accent: accent)

            HStack(alignment: .top, spacing: layout.spacing) {
                VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
                    contentStackHero(spec: spec, layout: layout, style: style, accent: accent)

                    if layout.showsAccentBar {
                        accentBar(accent: accent, style: style)
                    }
                }

                if let symbol = spec.symbol {
                    Image(systemName: symbol.name)
                        .font(.system(size: style.symbolSize))
                        .foregroundStyle(accent)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .opacity(0.85)
                }
            }

            actionBarIfNeeded(spec: spec, accent: accent)
        }
        .padding(style.padding)
    }

    private func posterTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Spacer(minLength: 0)

            VStack(alignment: .leading, spacing: 10) {
                if !spec.name.isEmpty {
                    Text(spec.name)
                        .font(style.nameTextStyle.font(fallback: .caption))
                        .foregroundStyle(.white.opacity(0.92))
                        .lineLimit(1)
                }

                if !spec.primaryText.isEmpty {
                    Text(spec.primaryText)
                        .font(style.primaryTextStyle.font(fallback: .title3))
                        .foregroundStyle(.white)
                        .lineLimit(layout.primaryLineLimit)
                }

                if let secondaryText = spec.secondaryText, !secondaryText.isEmpty {
                    Text(secondaryText)
                        .font(style.secondaryTextStyle.font(fallback: .caption2))
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(layout.secondaryLineLimit)
                }
            }
            .padding(style.padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [
                        Color.black.opacity(0.55),
                        Color.black.opacity(0.10),
                        Color.clear,
                    ],
                    startPoint: .bottom,
                    endPoint: .top
                )
            )
        }
    }

    private func weatherTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        WeatherTemplateView(
            spec: spec,
            family: family,
            context: context,
            accent: accent
        )
    }

    private func nextUpCalendarTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        NextUpCalendarTemplateView(
            spec: spec,
            family: family,
            context: context,
            accent: accent
        )
    }

    private func remindersTemplatePlaceholder(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow(spec: spec, style: style, accent: accent)

            VStack(alignment: layout.alignment.alignment, spacing: 10) {
                Text("Reminders")
                    .font(style.primaryTextStyle.font(fallback: .headline))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text("This template is not wired up yet.\nIt will render from real Reminders once enabled.")
                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)

                VStack(alignment: .leading, spacing: 8) {
                    placeholderReminderRow(title: "Buy milk", accent: accent, style: style)
                    placeholderReminderRow(title: "Reply to email", accent: accent, style: style)
                    placeholderReminderRow(title: "Book dentist", accent: accent, style: style)
                }
                .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
                .opacity(0.85)
            }
            .padding(.top, 2)

            if layout.showsAccentBar {
                accentBar(accent: accent, style: style)
            }
        }
    }

    private func placeholderReminderRow(title: String, accent: Color, style: StyleSpec) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(accent)
                .opacity(0.9)

            Text(title)
                .font(style.secondaryTextStyle.font(fallback: .caption))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
    }

    // MARK: - Building Blocks

    private func headerRow(spec: WidgetSpec, style: StyleSpec, accent: Color) -> some View {
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

    private func contentStackClassic(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
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

    private func contentStackHero(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
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

    private func imageRowClassic(symbol: WidgetSymbol, style: StyleSpec, accent: Color) -> some View {
        HStack {
            Spacer(minLength: 0)

            Image(systemName: symbol.name)
                .font(.system(size: style.symbolSize))
                .foregroundStyle(accent)
                .opacity(0.85)
        }
    }

    private func accentBar(accent: Color, style: StyleSpec) -> some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(accent)
            .frame(height: 5)
            .opacity(0.9)
    }

    // MARK: - Quick Actions (interactive widget buttons)

    private func actionBarIfNeeded(spec: WidgetSpec, accent: Color) -> some View {
        Group {
            if WidgetWeaverEntitlements.isProUnlocked,
               let bar = spec.actionBar,
               !bar.actions.isEmpty {
                actionBar(bar: bar, accent: accent)
                    .allowsHitTesting(context == .widget)
                    .opacity(context == .widget ? 1.0 : 0.85)
            }
        }
    }

    private func actionBar(bar: WidgetActionBarSpec, accent: Color) -> some View {
        HStack(spacing: 10) {
            ForEach(bar.actions) { action in
                widgetActionButton(action: action, barStyle: bar.style, accent: accent)
                    .frame(maxWidth: .infinity)
            }
        }
        .padding(.top, 10)
    }

    @ViewBuilder
    private func widgetActionButton(action: WidgetActionSpec, barStyle: WidgetActionButtonStyleToken, accent: Color) -> some View {
        switch action.kind {
        case .incrementVariable:
            Button(intent: WidgetWeaverIncrementVariableIntent(key: action.variableKey, amount: action.incrementAmount)) {
                actionButtonLabel(action: action, barStyle: barStyle, accent: accent)
            }
            .buttonStyle(.plain)

        case .setVariableToNow:
            Button(intent: WidgetWeaverSetVariableToNowIntent(key: action.variableKey, format: mapNowFormat(action.nowFormat))) {
                actionButtonLabel(action: action, barStyle: barStyle, accent: accent)
            }
            .buttonStyle(.plain)
        }
    }

    private func mapNowFormat(_ token: WidgetNowFormatToken) -> WidgetWeaverNowValueFormat {
        switch token {
        case .iso8601:
            return .iso8601
        case .unixSeconds:
            return .unixSeconds
        case .unixMilliseconds:
            return .unixSeconds
        case .dateOnly:
            return .dateOnly
        case .timeOnly:
            return .timeOnly
        }
    }

    private func actionButtonLabel(action: WidgetActionSpec, barStyle: WidgetActionButtonStyleToken, accent: Color) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        let backgroundOpacity: Double = (barStyle == .prominent) ? 0.20 : 0.12
        let borderOpacity: Double = (barStyle == .prominent) ? 0.30 : 0.16
        let minHeight: CGFloat = 44

        return HStack(spacing: 8) {
            if let systemImage = action.systemImage?.trimmingCharacters(in: .whitespacesAndNewlines),
               !systemImage.isEmpty {
                Image(systemName: systemImage)
                    .symbolRenderingMode(.hierarchical)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(accent)
            }

            Text(action.title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, minHeight: minHeight)
        .padding(.horizontal, 12)
        .background { shape.fill(accent.opacity(backgroundOpacity)) }
        .overlay { shape.strokeBorder(accent.opacity(borderOpacity), lineWidth: 1) }
        .contentShape(shape)
    }

    // MARK: - Background

    private func backgroundView(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        ZStack {
            if layout.template == .weather {
                weatherBackdrop(style: style, accent: accent)
            } else if layout.template == .poster,
                      let image = spec.image,
                      let uiImage = image.loadUIImageForRender(
                          family: family,
                          debugContext: WWPhotoLogContext(
                              renderContext: context.rawValue,
                              family: String(describing: family),
                              template: "poster",
                              specID: String(spec.id.uuidString.prefix(8)),
                              specName: spec.name
                          )
                      ) {
                Color(uiColor: .systemBackground)

                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .clipped()

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)
            } else if layout.template == .poster,
                      let image = spec.image,
                      let manifestFile = image.smartPhoto?.shuffleManifestFileName,
                      !manifestFile.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                let ctx = WWPhotoLogContext(
                    renderContext: context.rawValue,
                    family: String(describing: family),
                    template: "poster",
                    specID: String(spec.id.uuidString.prefix(8)),
                    specName: spec.name
                )
                let _ = WWPhotoDebugLog.appendLazy(
                    category: "photo.render",
                    throttleID: "poster.placeholder.\(spec.id.uuidString.prefix(8)).\(family)",
                    minInterval: 20.0,
                    context: ctx
                ) {
                    "poster: showing placeholder (image load returned nil) manifest=\(manifestFile)"
                }

                Color(uiColor: .systemBackground)

                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))

                VStack(spacing: 10) {
                    Image(systemName: "photo.on.rectangle.angled")
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(.secondary)

                    Text("No photo configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .padding(14)

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)

                backgroundEffects(style: style, accent: accent)
            } else {
                Color(uiColor: .systemBackground)

                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))

                Rectangle()
                    .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                    .opacity(style.backgroundOverlayOpacity)

                backgroundEffects(style: style, accent: accent)
            }
        }
        .ignoresSafeArea()
    }

    /// Weather uses a lot of `.ultraThinMaterial`. In WidgetKit, materials take their blur source from the
    /// widget container background. If the container background is clear, materials render as black.
    /// This backdrop is used as the widget container background so the weather glass has a real source.
    private func weatherBackdrop(style: StyleSpec, accent: Color) -> some View {
        let store = WidgetWeaverWeatherStore.shared
        let now = WidgetWeaverRenderClock.now
        let snapshot = store.snapshotForRender(context: context)

        let palette: WeatherPalette = {
            if let snapshot {
                return WeatherPalette.forSnapshot(snapshot, now: now, accent: accent)
            }
            return WeatherPalette.fallback(accent: accent)
        }()

        return ZStack {
            if style.background == .subtleMaterial {
                WeatherBackdropView(palette: palette, family: family)
            } else {
                Color(uiColor: .systemBackground)
                Rectangle()
                    .fill(style.background.shapeStyle(accent: accent))
            }

            Rectangle()
                .fill(style.backgroundOverlay.shapeStyle(accent: accent))
                .opacity(style.backgroundOverlayOpacity)

            backgroundEffects(style: style, accent: accent)
        }
        .ignoresSafeArea()
    }

    private func backgroundEffects(style: StyleSpec, accent: Color) -> some View {
        ZStack {
            if style.backgroundGlowEnabled {
                Circle()
                    .fill(accent)
                    .blur(radius: 70)
                    .opacity(0.18)
                    .offset(x: -120, y: -120)

                Circle()
                    .fill(accent)
                    .blur(radius: 90)
                    .opacity(0.12)
                    .offset(x: 140, y: 160)
            }
        }
    }
}

// MARK: - Background Modifier

private struct WidgetWeaverBackgroundModifier<Background: View>: ViewModifier {
    let family: WidgetFamily
    let context: WidgetWeaverRenderContext
    let background: Background

    func body(content: Content) -> some View {
        // iOS controls the outer widget mask.
        // Widget designs cannot change the widget’s shape.
        // The preview uses a stable approximation for the outer mask so sliders do not appear
        // to change the widget’s outer corners.
        let outerCornerRadius = Self.systemWidgetCornerRadius()

        switch context {
        case .widget:
            content
                .containerBackground(for: .widget) { background }
                .clipShape(ContainerRelativeShape())

        case .preview, .simulator:
            content
                .background(background)
                .clipShape(RoundedRectangle(cornerRadius: outerCornerRadius, style: .continuous))
        }
    }

    private static func systemWidgetCornerRadius() -> CGFloat {
        // The system widget corner radius is not exposed publicly.
        // Values are tuned to look close to iOS on iPhone and iPad.
        if UIDevice.current.userInterfaceIdiom == .pad { return 24 }
        return 22
    }
}
