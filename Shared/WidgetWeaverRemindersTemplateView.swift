//
//  WidgetWeaverRemindersTemplateView.swift
//  WidgetWeaver
//
//  Created by . . on 1/17/26.
//

import Foundation
import SwiftUI
import WidgetKit
import AppIntents

public struct WidgetWeaverRemindersTemplateView: View {
    public let spec: WidgetSpec
    public let family: WidgetFamily
    public let context: WidgetWeaverRenderContext
    public let layout: LayoutSpec
    public let style: StyleSpec
    public let accent: Color

    public init(
        spec: WidgetSpec,
        family: WidgetFamily,
        context: WidgetWeaverRenderContext,
        layout: LayoutSpec,
        style: StyleSpec,
        accent: Color
    ) {
        self.spec = spec
        self.family = family
        self.context = context
        self.layout = layout
        self.style = style
        self.accent = accent
    }

    public var body: some View {
        let store = WidgetWeaverRemindersStore.shared
        let snapshot = store.loadSnapshot()
        let lastError = store.loadLastError()
        let lastAction = store.loadLastAction()
        let config = (spec.remindersConfig ?? .default).normalised()

        let now = Date()
        let lastUpdatedAt = store.loadLastUpdatedAt()
        let gate = InteractivityGate(
            lastErrorKind: lastError?.kind,
            lastUpdatedAt: lastUpdatedAt,
            snapshotGeneratedAt: snapshot?.generatedAt,
            now: now
        )

        let widgetTapURL: URL? = {
            guard context == .widget else { return nil }
            if gate.canCompleteFromWidget == false {
                return Self.remindersAccessDeepLinkURL
            }
            return Self.remindersTapTargetURL(snapshot: snapshot, lastError: lastError)
        }()

        let content = VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            if !spec.name.isEmpty {
                headerRow()
            }

            VStack(alignment: layout.alignment.alignment, spacing: 10) {
                if let snapshot {
                    let model = Self.makeModel(snapshot: snapshot, config: config, now: now)

                    modeHeader(title: config.mode.displayName, progress: model.progress, showProgressBadge: config.showProgressBadge)

                    if let statusLine = gate.statusLine {
                        Text(statusLine)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                            .lineLimit(2)
                            .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
                    }

                    if model.isEmpty {
                        if let lastError {
                            remindersErrorBody(lastError: lastError)
                        } else {
                            emptyBody(text: "No reminders to show.")
                        }
                    } else {
                        remindersContent(model: model, config: config, gate: gate)
                    }

                    remindersFooter(lastAction: lastAction, lastUpdatedAt: lastUpdatedAt)
                } else if let lastError {
                    modeHeader(title: "Reminders", progress: nil, showProgressBadge: false)
                    remindersErrorBody(lastError: lastError)
                    if let lastAction {
                        remindersActionBody(lastAction: lastAction)
                    }
                } else {
                    remindersPlaceholder()
                }
            }
            .padding(.vertical, 2)

            if layout.showsAccentBar {
                accentBar()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: layout.alignment.swiftUIAlignment)

        if context == .widget {
            content.widgetURL(widgetTapURL)
        } else {
            content
        }
    }

    // MARK: - Header + chrome

    private func headerRow() -> some View {
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

    private func accentBar() -> some View {
        RoundedRectangle(cornerRadius: 999, style: .continuous)
            .fill(accent)
            .frame(height: 5)
            .opacity(0.9)
    }

    // MARK: - Widget tap behaviour

    private static let remindersAccessDeepLinkURL: URL = URL(string: "widgetweaver://reminders/access")!

    private static func remindersTapTargetURL(snapshot: WidgetWeaverRemindersSnapshot?, lastError: WidgetWeaverRemindersDiagnostics?) -> URL? {
        if snapshot == nil {
            return remindersAccessDeepLinkURL
        }

        guard let kind = lastError?.kind else {
            return nil
        }

        switch kind {
        case .notAuthorised, .writeOnly, .denied, .restricted:
            return remindersAccessDeepLinkURL
        case .ok, .error:
            return nil
        }
    }

    // MARK: - Model

    private struct Model: Sendable {
        var progress: (done: Int, total: Int)?
        var primaryItems: [WidgetWeaverReminderItem]
        var sections: [WidgetWeaverRemindersSection]
        var isEmpty: Bool {
            if !sections.isEmpty { return sections.allSatisfy { $0.itemIDs.isEmpty } }
            return primaryItems.isEmpty
        }
    }

    private static func makeModel(snapshot: WidgetWeaverRemindersSnapshot, config: WidgetWeaverRemindersConfig, now: Date) -> Model {
        let items = snapshot.items

        let itemsByID: [String: WidgetWeaverReminderItem] = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })

        let filtered: [WidgetWeaverReminderItem] = items.filter { item in
            if config.hideCompleted, item.isCompleted { return false }

            switch config.mode {
            case .today:
                return isDueTodayOrStartedToday(item: item, config: config, now: now)
            case .overdue:
                return isOverdue(item: item, now: now)
            case .soon:
                return isDueSoon(item: item, now: now, windowMinutes: config.soonWindowMinutes)
            case .flagged:
                return item.isFlagged
            case .focus:
                return true
            case .list:
                if config.selectedListIDs.isEmpty { return true }
                return config.selectedListIDs.contains(item.listID)
            }
        }

        let doneCount = filtered.filter { $0.isCompleted }.count
        let totalCount = filtered.count

        let progress: (done: Int, total: Int)? = {
            if config.mode == .focus || config.mode == .list || config.mode == .flagged {
                return nil
            }
            if totalCount <= 0 { return nil }
            return (doneCount, totalCount)
        }()

        // Precomputed mode snapshots can supply section structures or dense lists.
        if let modeSnapshot = snapshot.modes.first(where: { $0.mode == config.mode }) {
            if !modeSnapshot.sections.isEmpty {
                let sections = modeSnapshot.sections
                return Model(progress: progress, primaryItems: [], sections: sections)
            }

            if !modeSnapshot.itemIDs.isEmpty {
                let ids = modeSnapshot.itemIDs
                let primary = ids.compactMap { itemsByID[$0] }.filter { filtered.contains($0) }
                return Model(progress: progress, primaryItems: primary, sections: [])
            }
        }

        // Fallback: compute list for presentation.
        let sorted: [WidgetWeaverReminderItem] = sortItems(filtered, now: now)

        switch config.presentation {
        case .dense, .focus:
            return Model(progress: progress, primaryItems: Array(sorted.prefix(12)), sections: [])

        case .sectioned:
            let sections = buildSections(sorted)
            return Model(progress: progress, primaryItems: [], sections: sections)
        }
    }

    private static func sortItems(_ items: [WidgetWeaverReminderItem], now: Date) -> [WidgetWeaverReminderItem] {
        items.sorted { a, b in
            let ad = a.dueDate ?? Date.distantFuture
            let bd = b.dueDate ?? Date.distantFuture
            if ad != bd { return ad < bd }

            if a.isFlagged != b.isFlagged { return a.isFlagged && !b.isFlagged }

            return a.title.localizedCaseInsensitiveCompare(b.title) == .orderedAscending
        }
    }

    private static func buildSections(_ items: [WidgetWeaverReminderItem]) -> [WidgetWeaverRemindersSection] {
        let grouped = Dictionary(grouping: items, by: { $0.listTitle })
        let sortedKeys = grouped.keys.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }

        return sortedKeys.map { key in
            let listItems = grouped[key] ?? []
            let ids = listItems.map { $0.id }
            return WidgetWeaverRemindersSection(id: key, title: key, subtitle: nil, itemIDs: ids)
        }
    }

    private static func isDueTodayOrStartedToday(item: WidgetWeaverReminderItem, config: WidgetWeaverRemindersConfig, now: Date) -> Bool {
        // The Reminders app's "Today" view includes overdue items. This also ensures recurring
        // reminders that have not yet advanced their due date are still visible.
        if isOverdue(item: item, now: now) {
            return true
        }

        let cal = Calendar.autoupdatingCurrent
        let startOfDay = cal.startOfDay(for: now)
        guard let endOfDay = cal.date(byAdding: .day, value: 1, to: startOfDay) else {
            return false
        }

        if let due = item.dueDate {
            if due >= startOfDay && due < endOfDay {
                return true
            }
        }

        if config.includeStartDatesInToday, let start = item.startDate {
            if start >= startOfDay && start < endOfDay {
                return true
            }
        }

        return false
    }

    private static func isOverdue(item: WidgetWeaverReminderItem, now: Date) -> Bool {
        guard let due = item.dueDate else { return false }

        let cal = Calendar.autoupdatingCurrent
        let startOfToday = cal.startOfDay(for: now)

        // Treat due dates without a time as overdue only after the day has passed.
        if !item.dueHasTime {
            return due < startOfToday
        }

        return due < now
    }

    private static func isDueSoon(item: WidgetWeaverReminderItem, now: Date, windowMinutes: Int) -> Bool {
        guard let due = item.dueDate else { return false }
        let windowSeconds = TimeInterval(max(0, windowMinutes)) * 60.0
        let limit = now.addingTimeInterval(windowSeconds)
        return due >= now && due <= limit
    }

    // MARK: - Interactivity gate (stale snapshot protection)

    private struct InteractivityGate: Sendable {
        var canCompleteFromWidget: Bool
        var statusLine: String?

        init(
            lastErrorKind: WidgetWeaverRemindersDiagnostics.Kind?,
            lastUpdatedAt: Date?,
            snapshotGeneratedAt: Date?,
            now: Date
        ) {
            let hardStaleSeconds: TimeInterval = 60 * 60 * 24

            let permissionBlocked: Bool = {
                guard let kind = lastErrorKind else { return false }
                switch kind {
                case .notAuthorised, .writeOnly, .denied, .restricted:
                    return true
                case .ok, .error:
                    return false
                }
            }()

            let effectiveUpdatedAt = lastUpdatedAt ?? snapshotGeneratedAt

            if permissionBlocked {
                self.canCompleteFromWidget = false
                self.statusLine = "Taps disabled: Reminders access not granted. Tap to open Reminders settings."
                return
            }

            guard let effectiveUpdatedAt else {
                self.canCompleteFromWidget = false
                self.statusLine = "Taps disabled: No snapshot yet. Tap to open Reminders settings."
                return
            }

            if now.timeIntervalSince(effectiveUpdatedAt) > hardStaleSeconds {
                self.canCompleteFromWidget = false
                self.statusLine = "Taps disabled: Snapshot is out of date. Tap to open Reminders settings."
                return
            }

            if lastErrorKind == .error {
                self.canCompleteFromWidget = false
                self.statusLine = "Taps disabled: Reminders are unavailable. Tap to open Reminders settings."
                return
            }

            self.canCompleteFromWidget = true
            self.statusLine = nil
        }
    }

    // MARK: - Header

    @ViewBuilder
    func modeHeader(title: String, progress: (done: Int, total: Int)?, showProgressBadge: Bool) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(title)
                .font(style.primaryTextStyle.font(fallback: .headline))
                .foregroundStyle(.primary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if showProgressBadge, let progress {
                let done = max(0, progress.done)
                let total = max(0, progress.total)
                if total > 0 {
                    Text("\(done)/\(total)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 2)
                        .padding(.horizontal, 7)
                        .background(.thinMaterial, in: Capsule())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
    }

    // MARK: - Content rendering

    @ViewBuilder
    private func remindersContent(model: Model, config: WidgetWeaverRemindersConfig, gate: InteractivityGate) -> some View {
        switch config.presentation {
        case .dense:
            remindersDenseList(items: model.primaryItems, config: config, gate: gate)
        case .focus:
            remindersFocusList(items: model.primaryItems, config: config, gate: gate)
        case .sectioned:
            remindersSectionedList(sections: model.sections, snapshot: WidgetWeaverRemindersStore.shared.loadSnapshot(), config: config, gate: gate)
        }
    }

    private func remindersDenseList(items: [WidgetWeaverReminderItem], config: WidgetWeaverRemindersConfig, gate: InteractivityGate) -> some View {
        let maxRows: Int = {
            switch family {
            case .systemSmall:
                return 2
            case .systemMedium:
                return 4
            case .systemLarge:
                return 8
            default:
                return 4
            }
        }()

        let visible = Array(items.prefix(maxRows))

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(visible, id: \.id) { item in
                remindersRow(item: item, config: config, gate: gate)
            }
        }
        .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
    }

    private func remindersFocusList(items: [WidgetWeaverReminderItem], config: WidgetWeaverRemindersConfig, gate: InteractivityGate) -> some View {
        let visible = Array(items.prefix(3))

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(visible, id: \.id) { item in
                remindersRow(item: item, config: config, gate: gate)
            }
        }
        .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
    }

    private func remindersSectionedList(
        sections: [WidgetWeaverRemindersSection],
        snapshot: WidgetWeaverRemindersSnapshot?,
        config: WidgetWeaverRemindersConfig,
        gate: InteractivityGate
    ) -> some View {
        let itemsByID = snapshot?.itemsByID ?? [:]

        let maxSectionCount: Int = {
            switch family {
            case .systemSmall:
                return 1
            case .systemMedium:
                return 2
            case .systemLarge:
                return 4
            default:
                return 2
            }
        }()

        let visibleSections = Array(sections.prefix(maxSectionCount))

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(visibleSections, id: \.id) { section in
                let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty {
                    Text(title)
                        .font(style.secondaryTextStyle.font(fallback: .caption))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                let maxRows: Int = (family == .systemSmall) ? 2 : 3
                let visibleIDs = Array(section.itemIDs.prefix(maxRows))
                let visibleItems = visibleIDs.compactMap { itemsByID[$0] }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(visibleItems, id: \.id) { item in
                        remindersRow(item: item, config: config, gate: gate)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
    }

    @ViewBuilder
    private func remindersRow(item: WidgetWeaverReminderItem, config: WidgetWeaverRemindersConfig, gate: InteractivityGate) -> some View {
        let title = item.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeTitle = title.isEmpty ? "Untitled" : title

        let showsDue = (item.dueDate != nil) && (config.showDueTimes || !item.dueHasTime)

        let timeText: String? = {
            guard let due = item.dueDate else { return nil }
            if item.dueHasTime, config.showDueTimes {
                return due.formatted(date: .omitted, time: .shortened)
            }
            return due.formatted(date: .abbreviated, time: .omitted)
        }()

        if context == .widget, gate.canCompleteFromWidget, !item.isCompleted {
            Button(intent: WidgetWeaverCompleteReminderWidgetIntent(reminderID: item.id)) {
                rowBody(title: safeTitle, showsDue: showsDue, timeText: timeText, isFlagged: item.isFlagged)
            }
            .buttonStyle(.plain)
        } else {
            rowBody(title: safeTitle, showsDue: showsDue, timeText: timeText, isFlagged: item.isFlagged)
        }
    }

    private func rowBody(title: String, showsDue: Bool, timeText: String?, isFlagged: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "circle")
                .font(.system(size: 14, weight: .regular))
                .foregroundStyle(accent)
                .opacity(0.9)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(style.secondaryTextStyle.font(fallback: .caption))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    if isFlagged {
                        Image(systemName: "flag.fill")
                            .font(.caption2)
                            .foregroundStyle(accent)
                    }

                    Spacer(minLength: 0)
                }

                if showsDue, let timeText {
                    Text(timeText)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
    }

    // MARK: - Empty/error/footer

    private func emptyBody(text: String) -> some View {
        Text(text)
            .font(style.secondaryTextStyle.font(fallback: .caption2))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
            .lineLimit(3)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
    }

    private func remindersFooter(lastAction: WidgetWeaverRemindersActionDiagnostics?, lastUpdatedAt: Date?) -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: 6) {
            if let lastAction {
                remindersActionBody(lastAction: lastAction)
            }

            if let lastUpdatedAt {
                Text("Updated \(lastUpdatedAt.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
            }
        }
        .padding(.top, 2)
    }

    private func remindersErrorBody(lastError: WidgetWeaverRemindersDiagnostics) -> some View {
        let message = lastError.message.trimmingCharacters(in: .whitespacesAndNewlines)
        let safeMessage = message.isEmpty ? "No details." : message

        let displayMessage: String = {
            switch lastError.kind {
            case .ok:
                return safeMessage
            case .notAuthorised, .denied, .restricted:
                return "Reminders access not granted."
            case .writeOnly:
                return "Reminders access is write-only."
            case .error:
                return "Reminders unavailable: \(safeMessage)"
            }
        }()

        return VStack(alignment: layout.alignment.alignment, spacing: 6) {
            Text(displayMessage)
                .font(style.secondaryTextStyle.font(fallback: .caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: context != .widget)

            Text(lastError.at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func remindersActionBody(lastAction: WidgetWeaverRemindersActionDiagnostics) -> some View {
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
                .fixedSize(horizontal: false, vertical: context != .widget)

            Text(lastAction.at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}
