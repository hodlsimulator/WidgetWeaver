//
//  WidgetWeaverRemindersConfig.swift
//  WidgetWeaver
//
//  Created by . . on 1/14/26.
//

import Foundation

// MARK: - Reminders configuration (schema-only)

/// High-level content mode for the Reminders template.
public enum WidgetWeaverRemindersMode: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case today
    case overdue
    case soon
    case flagged
    case focus
    case list

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .today: return "Today"
        case .overdue: return "Overdue"
        case .soon: return "Soon"
        case .flagged: return "Priority"
        case .focus: return "Focus"
        case .list: return "List"
        }
    }
}

/// Visual style for how reminders are grouped/emphasised.
public enum WidgetWeaverRemindersPresentation: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case dense
    case focus
    case sectioned

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .dense: return "Dense"
        case .focus: return "Focus"
        case .sectioned: return "Sectioned"
        }
    }
}

/// Per-widget configuration for the Reminders template.
///
/// Notes:
/// - List identifiers are `EKCalendar.calendarIdentifier` values (EventKit reminder calendars).
/// - This file intentionally contains schema types only (Phase 0.2).
public struct WidgetWeaverRemindersConfig: Codable, Hashable, Sendable {
    /// Sensible defaults for future decoding when keys are missing.
    public static let defaultSoonWindowMinutes: Int = 60 * 24

    /// Content mode for this widget instance.
    public var mode: WidgetWeaverRemindersMode

    /// Visual grouping / emphasis.
    public var presentation: WidgetWeaverRemindersPresentation

    /// Reminder list IDs to include (EKCalendar.calendarIdentifier).
    ///
    /// An empty array means "all lists".
    public var selectedListIDs: [String]

    /// Filters completed reminders from the results.
    public var hideCompleted: Bool

    /// Shows due times for reminders that have a time component.
    public var showDueTimes: Bool

    /// Allows the template to show a compact progress badge (for example, "3/7").
    public var showProgressBadge: Bool

    /// Used when `mode == .soon`.
    public var soonWindowMinutes: Int

    /// Used when `mode == .today`.
    /// When true, reminders that start today can be included alongside due-today items.
    public var includeStartDatesInToday: Bool

    public init(
        mode: WidgetWeaverRemindersMode = .today,
        presentation: WidgetWeaverRemindersPresentation = .dense,
        selectedListIDs: [String] = [],
        hideCompleted: Bool = true,
        showDueTimes: Bool = true,
        showProgressBadge: Bool = true,
        soonWindowMinutes: Int = WidgetWeaverRemindersConfig.defaultSoonWindowMinutes,
        includeStartDatesInToday: Bool = true
    ) {
        self.mode = mode
        self.presentation = presentation
        self.selectedListIDs = selectedListIDs
        self.hideCompleted = hideCompleted
        self.showDueTimes = showDueTimes
        self.showProgressBadge = showProgressBadge
        self.soonWindowMinutes = soonWindowMinutes
        self.includeStartDatesInToday = includeStartDatesInToday

        self = self.normalised()
    }

    public static var `default`: WidgetWeaverRemindersConfig {
        WidgetWeaverRemindersConfig()
    }

    public func normalised() -> WidgetWeaverRemindersConfig {
        var c = self

        // Keep list IDs non-empty (no trimming/normalisation beyond this; EventKit owns the format).
        c.selectedListIDs = c.selectedListIDs.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        // Avoid pathological values. The UI layer can apply a more opinionated range later.
        let minMinutes = 15
        let maxMinutes = 60 * 24 * 31
        c.soonWindowMinutes = max(minMinutes, min(c.soonWindowMinutes, maxMinutes))

        return c
    }

    // MARK: Codable compatibility (future-proofing)

    private enum CodingKeys: String, CodingKey {
        case mode
        case presentation
        case selectedListIDs
        case hideCompleted
        case showDueTimes
        case showProgressBadge
        case soonWindowMinutes
        case includeStartDatesInToday
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let mode = (try? c.decode(WidgetWeaverRemindersMode.self, forKey: .mode)) ?? .today
        let presentation = (try? c.decode(WidgetWeaverRemindersPresentation.self, forKey: .presentation)) ?? .dense
        let selectedListIDs = (try? c.decode([String].self, forKey: .selectedListIDs)) ?? []
        let hideCompleted = (try? c.decode(Bool.self, forKey: .hideCompleted)) ?? true
        let showDueTimes = (try? c.decode(Bool.self, forKey: .showDueTimes)) ?? true
        let showProgressBadge = (try? c.decode(Bool.self, forKey: .showProgressBadge)) ?? true
        let soonWindowMinutes = (try? c.decode(Int.self, forKey: .soonWindowMinutes)) ?? Self.defaultSoonWindowMinutes
        let includeStartDatesInToday = (try? c.decode(Bool.self, forKey: .includeStartDatesInToday)) ?? true

        self.init(
            mode: mode,
            presentation: presentation,
            selectedListIDs: selectedListIDs,
            hideCompleted: hideCompleted,
            showDueTimes: showDueTimes,
            showProgressBadge: showProgressBadge,
            soonWindowMinutes: soonWindowMinutes,
            includeStartDatesInToday: includeStartDatesInToday
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(presentation, forKey: .presentation)
        try c.encode(selectedListIDs, forKey: .selectedListIDs)
        try c.encode(hideCompleted, forKey: .hideCompleted)
        try c.encode(showDueTimes, forKey: .showDueTimes)
        try c.encode(showProgressBadge, forKey: .showProgressBadge)
        try c.encode(soonWindowMinutes, forKey: .soonWindowMinutes)
        try c.encode(includeStartDatesInToday, forKey: .includeStartDatesInToday)
    }
}
