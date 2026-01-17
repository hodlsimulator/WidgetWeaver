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

        return VStack(alignment: layout.alignment.alignment, spacing: layout.spacing) {
            headerRow()

            VStack(alignment: layout.alignment.alignment, spacing: 10) {
                if let snapshot {
                    let now = Date()
                    let lastUpdatedAt = store.loadLastUpdatedAt()
                    let gate = InteractivityGate(
                        lastErrorKind: lastError?.kind,
                        lastUpdatedAt: lastUpdatedAt,
                        snapshotGeneratedAt: snapshot.generatedAt,
                        now: now
                    )

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

    // MARK: - Model

    private struct RenderSection: Identifiable, Hashable {
        var id: String
        var title: String
        var subtitle: String?
        var items: [WidgetWeaverReminderItem]
    }

    private struct Model {
        var items: [WidgetWeaverReminderItem]
        var sections: [RenderSection]
        var usesSections: Bool
        var progress: (done: Int, total: Int)?

        var isEmpty: Bool {
            if usesSections {
                return sections.allSatisfy { $0.items.isEmpty }
            }
            return items.isEmpty
        }
    }

    private static func makeModel(snapshot: WidgetWeaverRemindersSnapshot, config: WidgetWeaverRemindersConfig, now: Date) -> Model {
        let includeCompletedForProgress = Self.remindersItems(snapshot: snapshot, config: config, now: now, includeCompleted: true, applyFocusMode: false)
        let done = includeCompletedForProgress.filter { $0.isCompleted }.count
        let total = includeCompletedForProgress.count

        let progress: (done: Int, total: Int)? = {
            guard total > 0 else { return nil }
            return (done: done, total: total)
        }()

        let items = Self.remindersItems(snapshot: snapshot, config: config, now: now, includeCompleted: !config.hideCompleted, applyFocusMode: true)
        let sections = Self.remindersSections(snapshot: snapshot, config: config, now: now, includeCompleted: !config.hideCompleted)
        let usesSections = (config.presentation == .sectioned) && !sections.isEmpty

        return Model(items: items, sections: sections, usesSections: usesSections, progress: progress)
    }

    private static func remindersSections(
        snapshot: WidgetWeaverRemindersSnapshot,
        config: WidgetWeaverRemindersConfig,
        now: Date,
        includeCompleted: Bool
    ) -> [RenderSection] {
        guard let modeSnapshot = snapshot.modes.first(where: { $0.mode == config.mode }) else { return [] }
        guard !modeSnapshot.sections.isEmpty else { return [] }

        let byID = snapshot.itemsByID
        let allowedListIDs: Set<String> = Set(config.selectedListIDs)

        func listPass(_ item: WidgetWeaverReminderItem) -> Bool {
            if allowedListIDs.isEmpty { return true }
            return allowedListIDs.contains(item.listID)
        }

        func completionPass(_ item: WidgetWeaverReminderItem) -> Bool {
            if includeCompleted { return true }
            return !item.isCompleted
        }

        let predicate = Self.modePredicate(config: config, now: now)

        return modeSnapshot.sections.enumerated().compactMap { idx, section in
            let sectionID: String = {
                let trimmed = section.id.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty { return trimmed }

                let title = section.title.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { return "\(config.mode.rawValue).title.\(title)" }

                return "\(config.mode.rawValue).idx.\(idx)"
            }()

            let items = section.itemIDs
                .compactMap { byID[$0] }
                .filter(listPass)
                .filter(completionPass)
                .filter(predicate)

            guard !items.isEmpty else { return nil }

            return RenderSection(
                id: sectionID,
                title: section.title,
                subtitle: section.subtitle,
                items: items
            )
        }
    }

    private static func remindersItems(
        snapshot: WidgetWeaverRemindersSnapshot,
        config: WidgetWeaverRemindersConfig,
        now: Date,
        includeCompleted: Bool,
        applyFocusMode: Bool
    ) -> [WidgetWeaverReminderItem] {
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

        if !includeCompleted {
            candidates = candidates.filter { !$0.isCompleted }
        }

        let predicate = Self.modePredicate(config: config, now: now)
        let filtered = candidates.filter(predicate)

        if hasPrecomputedOrdering {
            if applyFocusMode, config.mode == .focus {
                if let first = filtered.first { return [first] }
                return []
            }
            return filtered
        }

        let sorted: [WidgetWeaverReminderItem] = {
            switch config.mode {
            case .list:
                return filtered.sorted(by: compareList)
            default:
                return filtered.sorted(by: compareGeneral)
            }
        }()

        if applyFocusMode, config.mode == .focus {
            if let first = sorted.first { return [first] }
            return []
        }

        return sorted
    }

    private static func modePredicate(config: WidgetWeaverRemindersConfig, now: Date) -> (WidgetWeaverReminderItem) -> Bool {
        let cal = Calendar.current
        let startOfToday = cal.startOfDay(for: now)
        let endOfToday = cal.date(byAdding: .day, value: 1, to: startOfToday) ?? now

        switch config.mode {
        case .today:
            return { item in
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

        case .overdue:
            return { item in
                guard let due = item.dueDate else { return false }
                return due < startOfToday
            }

        case .soon:
            let windowSeconds = TimeInterval(config.soonWindowMinutes * 60)
            let end = now.addingTimeInterval(windowSeconds)
            return { item in
                guard let due = item.dueDate else { return false }
                return due >= now && due <= end
            }

        case .flagged:
            return { $0.isFlagged }

        case .focus:
            return { _ in true }

        case .list:
            return { _ in true }
        }
    }

    // MARK: - Mode header + progress

    @ViewBuilder
    private func modeHeader(title: String, progress: (done: Int, total: Int)?, showProgressBadge: Bool) -> some View {
        let titleView = Text(title)
            .font(style.primaryTextStyle.font(fallback: .headline))
            .foregroundStyle(.primary)
            .lineLimit(1)

        let shouldShowBadge = showProgressBadge && (progress?.total ?? 0) > 0

        if layout.alignment == .centre {
            VStack(spacing: 4) {
                titleView

                if shouldShowBadge, let progress {
                    remindersProgressPill(done: progress.done, total: progress.total)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                titleView

                Spacer(minLength: 0)

                if shouldShowBadge, let progress {
                    remindersProgressPill(done: progress.done, total: progress.total)
                }
            }
        }
    }

    private func remindersProgressPill(done: Int, total: Int) -> some View {
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

    // MARK: - Content

    @ViewBuilder
    private func remindersContent(model: Model, config: WidgetWeaverRemindersConfig, gate: InteractivityGate) -> some View {
        if model.usesSections {
            remindersSectionedRows(sections: model.sections, config: config, gate: gate)
        } else {
            remindersDenseRows(items: model.items, config: config, gate: gate)
        }
    }

    private func remindersDenseRows(items: [WidgetWeaverReminderItem], config: WidgetWeaverRemindersConfig, gate: InteractivityGate) -> some View {
        let maxRows = remindersMaxRows(for: family, presentation: config.presentation)
        let limited = Array(items.prefix(maxRows))

        return VStack(alignment: .leading, spacing: 8) {
            ForEach(limited) { item in
                remindersRow(item: item, config: config, gate: gate)
            }
        }
        .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
        .opacity(0.92)
    }

    private func remindersSectionedRows(sections: [RenderSection], config: WidgetWeaverRemindersConfig, gate: InteractivityGate) -> some View {
        let maxRows = remindersMaxRows(for: family, presentation: config.presentation)

        var remaining = maxRows
        let visibleSections: [RenderSection] = sections.compactMap { section in
            guard remaining > 0 else { return nil }
            let visible = Array(section.items.prefix(remaining))
            remaining -= visible.count

            guard !visible.isEmpty else { return nil }

            return RenderSection(
                id: section.id,
                title: section.title,
                subtitle: section.subtitle,
                items: visible
            )
        }

        return VStack(alignment: .leading, spacing: 10) {
            ForEach(visibleSections) { section in
                VStack(alignment: .leading, spacing: 6) {
                    if !section.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || section.subtitle != nil {
                        remindersSectionHeader(title: section.title, subtitle: section.subtitle)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(section.items) { item in
                            remindersRow(item: item, config: config, gate: gate)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
        .opacity(0.92)
    }

    private func remindersSectionHeader(title: String, subtitle: String?) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(title)
                    .font(style.secondaryTextStyle.font(fallback: .caption2).weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if let subtitle, !subtitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(subtitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary.opacity(0.9))
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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

    // MARK: - Interactivity gating (Phase 5.2.3)

    private struct InteractivityGate {
        var canCompleteFromWidget: Bool
        var statusLine: String?

        private static let hardStaleSeconds: TimeInterval = 60 * 60 * 24

        init(
            lastErrorKind: WidgetWeaverRemindersDiagnostics.Kind?,
            lastUpdatedAt: Date?,
            snapshotGeneratedAt: Date?,
            now: Date = Date()
        ) {
            let effectiveUpdatedAt = lastUpdatedAt ?? snapshotGeneratedAt

            let permissionBlocked: Bool = {
                guard let kind = lastErrorKind else { return false }
                switch kind {
                case .ok:
                    return false
                case .notAuthorised, .writeOnly, .denied, .restricted:
                    return true
                case .error:
                    return false
                }
            }()

            if permissionBlocked {
                self.canCompleteFromWidget = false
                self.statusLine = "Taps disabled: Reminders access not granted."
                return
            }

            // Snapshot presence is required for reliable completion UI in the widget.
            guard let effectiveUpdatedAt else {
                self.canCompleteFromWidget = false
                self.statusLine = "Taps disabled: No snapshot yet. Open the app to refresh."
                return
            }

            let isHardStale = now.timeIntervalSince(effectiveUpdatedAt) > Self.hardStaleSeconds
            if isHardStale {
                self.canCompleteFromWidget = false
                self.statusLine = "Taps disabled: Snapshot is out of date. Open the app to refresh."
                return
            }

            // If the last known state is a generic refresh error, pessimistically disable completion
            // until the app refreshes the snapshot successfully.
            if lastErrorKind == .error {
                self.canCompleteFromWidget = false
                self.statusLine = "Taps disabled: Reminders are unavailable. Open the app to refresh."
                return
            }

            self.canCompleteFromWidget = true
            self.statusLine = nil
        }
    }

    // MARK: - Row

    @ViewBuilder
    private func remindersRow(item: WidgetWeaverReminderItem, config: WidgetWeaverRemindersConfig, gate: InteractivityGate) -> some View {
        let cleanedID = item.id.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
        let isInteractive = (context == .widget) && !item.isCompleted && !cleanedID.isEmpty && gate.canCompleteFromWidget

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

    // MARK: - Footer + states

    @ViewBuilder
    private func remindersFooter(lastAction: WidgetWeaverRemindersActionDiagnostics?, lastUpdatedAt: Date?) -> some View {
        if let lastAction {
            remindersActionBody(lastAction: lastAction)
        } else if let updatedAt = lastUpdatedAt {
            Text("Updated \(updatedAt.formatted(date: .abbreviated, time: .shortened))")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func emptyBody(text: String) -> some View {
        Text(text)
            .font(style.secondaryTextStyle.font(fallback: .caption2))
            .foregroundStyle(.secondary)
            .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func remindersErrorBody(lastError: WidgetWeaverRemindersDiagnostics) -> some View {
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
                .fixedSize(horizontal: false, vertical: true)

            Text(lastAction.at.formatted(date: .abbreviated, time: .shortened))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }

    private func remindersPlaceholder() -> some View {
        VStack(alignment: layout.alignment.alignment, spacing: 10) {
            modeHeader(title: "Reminders", progress: nil, showProgressBadge: false)

            Text("No snapshot yet.\nOpen WidgetWeaver to enable Reminders access and refresh.")
                .font(style.secondaryTextStyle.font(fallback: .caption2))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(layout.alignment == .centre ? .center : .leading)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                placeholderReminderRow(title: "Buy milk")
                placeholderReminderRow(title: "Reply to email")
                placeholderReminderRow(title: "Book dentist")
            }
            .frame(maxWidth: .infinity, alignment: layout.alignment.swiftUIAlignment)
            .opacity(0.85)
        }
    }

    private func placeholderReminderRow(title: String) -> some View {
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
