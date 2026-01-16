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

    @AppStorage(WidgetWeaverRemindersStore.Keys.snapshotData, store: AppGroup.userDefaults)
    private var remindersSnapshotData: Data = Data()

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastUpdatedAt, store: AppGroup.userDefaults)
    private var remindersLastUpdatedAt: Double = 0

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastErrorKind, store: AppGroup.userDefaults)
    private var remindersLastErrorKind: String = ""

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastErrorMessage, store: AppGroup.userDefaults)
    private var remindersLastErrorMessage: String = ""

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastErrorAt, store: AppGroup.userDefaults)
    private var remindersLastErrorAt: Double = 0

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastActionKind, store: AppGroup.userDefaults)
    private var remindersLastActionKind: String = ""

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastActionMessage, store: AppGroup.userDefaults)
    private var remindersLastActionMessage: String = ""

    @AppStorage(WidgetWeaverRemindersStore.Keys.lastActionAt, store: AppGroup.userDefaults)
    private var remindersLastActionAt: Double = 0


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
        let _ = remindersSnapshotData
        let _ = remindersLastUpdatedAt
        let _ = remindersLastErrorKind
        let _ = remindersLastErrorMessage
        let _ = remindersLastErrorAt
        let _ = remindersLastActionKind
        let _ = remindersLastActionMessage
        let _ = remindersLastActionAt

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
                remindersTemplate(spec: resolved, layout: layout, style: style, accent: accent)
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

    
    private func remindersTemplate(spec: WidgetSpec, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let store = WidgetWeaverRemindersStore.shared
        let snapshot = store.loadSnapshot()
        let lastError = store.loadLastError()
        let lastAction = store.loadLastAction()
        let config = (spec.remindersConfig ?? .default).normalised()

        if let snapshot {
            let now = Date()
            let items = remindersFilteredItems(snapshot: snapshot, config: config, now: now)
            return AnyView(
                VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
                    headerRow(spec: spec, style: style, accent: accent)

                    VStack(alignment: layout.alignment.alignment, spacing: 10) {
                        Text(config.mode.displayName)
                            .font(style.primaryTextStyle.font(fallback: .headline))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        if items.isEmpty {
                            if let lastError {
                                remindersErrorBody(lastError: lastError, layout: layout, style: style)
                            } else {
                                Text("No reminders to show.")
                                    .font(style.secondaryTextStyle.font(fallback: .caption2))
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                                    .lineLimit(2)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        } else {
                            remindersRows(items: items, config: config, layout: layout, style: style, accent: accent)
                        }

                        if let lastAction {
                            remindersActionBody(lastAction: lastAction, layout: layout, style: style)
                        } else if let updatedAt = store.loadLastUpdatedAt() {
                            Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    .padding(.top, 2)

                    if layout.showsAccentBar {
                        accentBar(accent: accent, style: style)
                    }
                }
            )
        }

        if let lastError {
            return AnyView(
                VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
                    headerRow(spec: spec, style: style, accent: accent)

                    VStack(alignment: layout.alignment.alignment, spacing: 10) {
                        Text("Reminders")
                            .font(style.primaryTextStyle.font(fallback: .headline))
                            .foregroundStyle(.primary)
                            .lineLimit(1)

                        remindersErrorBody(lastError: lastError, layout: layout, style: style)

                        if let lastAction {
                            remindersActionBody(lastAction: lastAction, layout: layout, style: style)
                        }
                    }
                    .padding(.top, 2)

                    if layout.showsAccentBar {
                        accentBar(accent: accent, style: style)
                    }
                }
            )
        }

        return AnyView(remindersTemplatePlaceholder(spec: spec, layout: layout, style: style, accent: accent))
    }

    private func remindersErrorBody(lastError: WidgetWeaverRemindersDiagnostics, layout: LayoutSpec, style: StyleSpec) -> some View {
        let kindText: String = {
            switch lastError.kind {
            case .ok:
                return "OK"
            case .notAuthorised:
                return "Not authorised"
            case .writeOnly:
                return "Write-only"
            case .denied:
                return "Denied"
            case .restricted:
                return "Restricted"
            case .error:
                return "Error"
            }
        }()

        let message = lastError.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeMessage = message.isEmpty ? "No details." : message

        return VStack(alignment: layout.alignment.alignment, spacing: 6) {
            Text("\(kindText): \(safeMessage)")
                .font(style.secondaryTextStyle.font(fallback: .caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(lastError.at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func remindersActionBody(lastAction: WidgetWeaverRemindersActionDiagnostics, layout: LayoutSpec, style: StyleSpec) -> some View {
        let message = lastAction.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeMessage = message.isEmpty ? "No details." : message

        let displayMessage: String = {
            switch lastAction.kind {
            case .completed:
                return safeMessage
            case .noop:
                return "No action: \(safeMessage)"
            case .error:
                return "Action failed: \(safeMessage)"
            }
        }()

        return VStack(alignment: layout.alignment.alignment, spacing: 6) {
            Text(displayMessage)
                .font(style.secondaryTextStyle.font(fallback: .caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            Text(lastAction.at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }


    private func remindersRows(items: [WidgetWeaverReminderItem], config: WidgetWeaverRemindersConfig, layout: LayoutSpec, style: StyleSpec, accent: Color) -> some View {
        let maxRows = remindersMaxRows(for: family, presentation: config.presentation)
        let limited = Array(items.prefix(maxRows))

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(limited) { item in
                remindersRow(item: item, config: config, style: style, accent: accent)
            }
        }
        .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
        .opacity(0.92)
    }

    @ViewBuilder
    private func remindersRow(item: WidgetWeaverReminderItem, config: WidgetWeaverRemindersConfig, style: StyleSpec, accent: Color) -> some View {
        let cleanedID = item.id.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let isInteractive = (context == .widget) && !item.isCompleted && !cleanedID.isEmpty

        let row = HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: item.isCompleted ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(accent)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.title)
                    .font(style.secondaryTextStyle.font(fallback: .caption))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                if let dueText = remindersDueText(for: item, showDueTimes: config.showDueTimes) {
                    Text(dueText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())

        if isInteractive {
            Button(intent: WidgetWeaverCompleteReminderWidgetIntent(reminderID: cleanedID)) {
                row
            }
            .buttonStyle(.plain)
        } else {
            row
        }
    }

    private func remindersDueText(for item: WidgetWeaverReminderItem, showDueTimes: Bool) -> String? {
        guard let dueDate = item.dueDate else { return nil }
        if showDueTimes && item.dueHasTime {
            return dueDate.formatted(date: .abbreviated, time: .shortened)
        }
        return dueDate.formatted(date: .abbreviated, time: .omitted)
    }

    private func remindersMaxRows(for family: WidgetFamily, presentation: WidgetWeaverRemindersPresentation) -> Int {
        if presentation == .focus { return 1 }

        switch family {
        case .systemSmall:
            return 3
        case .systemMedium:
            return 5
        case .systemLarge:
            return 8
        case .systemExtraLarge:
            return 10
        case .accessoryRectangular:
            return 2
        default:
            return 3
        }
    }

    private func remindersFilteredItems(snapshot: WidgetWeaverRemindersSnapshot, config: WidgetWeaverRemindersConfig, now: Date) -> [WidgetWeaverReminderItem] {
        func compareGeneral(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let da = a.dueDate ?? a.startDate ?? Date.distantFuture
            let db = b.dueDate ?? b.startDate ?? Date.distantFuture

            if da != db { return da < db }

            let titleComp = a.title.localizedCaseInsensitiveCompare(b.title)
            if titleComp != .orderedSame { return titleComp == .orderedAscending }

            return a.id < b.id
        }

        func compareList(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let listComp = a.listTitle.localizedCaseInsensitiveCompare(b.listTitle)
            if listComp != .orderedSame { return listComp == .orderedAscending }
            return compareGeneral(a, b)
        }

        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        let byID = snapshot.itemsByID
        let modeSnapshot = snapshot.modes.first(where: { $0.mode == config.mode })
        let hasPrecomputedOrdering = (modeSnapshot != nil) && !(modeSnapshot?.itemIDs.isEmpty ?? true)

        var candidates: [WidgetWeaverReminderItem]
        if let modeSnapshot, !modeSnapshot.itemIDs.isEmpty {
            candidates = modeSnapshot.itemIDs.compactMap { byID[$0] }
        } else {
            candidates = snapshot.items
        }

        if !config.selectedListIDs.isEmpty {
            let allowed = Set(config.selectedListIDs)
            candidates = candidates.filter { allowed.contains($0.listID) }
        }

        if config.hideCompleted {
            candidates = candidates.filter { !$0.isCompleted }
        }

        switch config.mode {
        case .today:
            let filtered = candidates.filter { item in
                let dueIsToday: Bool = {
                    guard let due = item.dueDate else { return false }
                    return due >= startOfToday && due < endOfToday
                }()

                if dueIsToday {
                    return true
                }

                guard config.includeStartDatesInToday else {
                    return false
                }

                guard let start = item.startDate else {
                    return false
                }

                return start >= startOfToday && start < endOfToday
            }

            if hasPrecomputedOrdering {
                return filtered
            }

            return filtered.sorted(by: compareGeneral)

        case .overdue:
            let filtered = candidates.filter { item in
                guard let due = item.dueDate else { return false }
                return due < startOfToday
            }

            if hasPrecomputedOrdering {
                return filtered
            }

            return filtered.sorted(by: compareGeneral)

        case .soon:
            let windowSeconds = TimeInterval(config.soonWindowMinutes * 60)
            let end = now.addingTimeInterval(windowSeconds)

            let filtered = candidates.filter { item in
                guard let due = item.dueDate else { return false }
                return due >= now && due <= end
            }

            if hasPrecomputedOrdering {
                return filtered
            }

            return filtered.sorted(by: compareGeneral)

        case .flagged:
            let filtered = candidates.filter { $0.isFlagged }

            if hasPrecomputedOrdering {
                return filtered
            }

            return filtered.sorted(by: compareGeneral)

        case .focus:
            if hasPrecomputedOrdering {
                if let first = candidates.first {
                    return [first]
                }
                return []
            }

            let sorted = candidates.sorted(by: compareGeneral)
            if let first = sorted.first {
                return [first]
            }

            return []

        case .list:
            if hasPrecomputedOrdering {
                return candidates
            }

            return candidates.sorted(by: compareList)
        }
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

}
