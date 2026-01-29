//
//  WidgetWeaverRemindersModels.swift
//  WidgetWeaver
//
//  Created by . . on 1/15/26.
//

import Foundation

// MARK: - Reminders snapshot models (Phase 2)

/// A widget-safe representation of a single reminder item.
///
/// Notes:
/// - `id` is an `EKReminder.calendarItemIdentifier`.
/// - `listID` is an `EKCalendar.calendarIdentifier` (for calendars of type `.reminder`).
/// - This intentionally avoids carrying `EventKit` types across module boundaries.
public struct WidgetWeaverReminderItem: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String

    public var dueDate: Date?
    public var dueHasTime: Bool

    public var startDate: Date?
    public var startHasTime: Bool

    /// EventKit priority (0 = none; 1 is highest priority).
    ///
    /// Notes:
    /// - `EKReminder.priority` uses a numeric scale where lower numbers are higher priority.
    /// - Reminders Smart Stack v1 used `isFlagged` as a high-priority approximation.
    /// - This value supports Smart Stack v2 ordering while keeping v1 behaviour unchanged.
    public var priority: Int

    public var isCompleted: Bool
    public var isFlagged: Bool
    public var isRecurring: Bool

    public var listID: String
    public var listTitle: String

    public init(
        id: String,
        title: String,
        dueDate: Date? = nil,
        dueHasTime: Bool = false,
        startDate: Date? = nil,
        startHasTime: Bool = false,
        priority: Int = 0,
        isCompleted: Bool = false,
        isFlagged: Bool = false,
        isRecurring: Bool = false,
        listID: String,
        listTitle: String
    ) {
        self.id = id
        self.title = title
        self.dueDate = dueDate
        self.dueHasTime = dueHasTime
        self.startDate = startDate
        self.startHasTime = startHasTime
        self.priority = priority
        self.isCompleted = isCompleted
        self.isFlagged = isFlagged
        self.isRecurring = isRecurring
        self.listID = listID
        self.listTitle = listTitle

        self = self.normalised()
    }

    public func normalised() -> WidgetWeaverReminderItem {
        var r = self

        r.id = r.id.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedTitle = r.title.trimmingCharacters(in: .whitespacesAndNewlines)
        r.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle

        r.listID = r.listID.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedListTitle = r.listTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        r.listTitle = trimmedListTitle.isEmpty ? "Untitled" : trimmedListTitle

        // EventKit documents priority as 0-9 (0 = none). Clamp to a sensible range.
        r.priority = max(0, min(r.priority, 9))

        return r
    }

    // MARK: Codable compatibility (future-proofing)

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case dueDate
        case dueHasTime
        case startDate
        case startHasTime
        case priority
        case isCompleted
        case isFlagged
        case isRecurring
        case listID
        case listTitle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let id = (try? c.decode(String.self, forKey: .id)) ?? ""
        let title = (try? c.decode(String.self, forKey: .title)) ?? ""

        let dueDate = try? c.decode(Date.self, forKey: .dueDate)
        let dueHasTime = (try? c.decode(Bool.self, forKey: .dueHasTime)) ?? false

        let startDate = try? c.decode(Date.self, forKey: .startDate)
        let startHasTime = (try? c.decode(Bool.self, forKey: .startHasTime)) ?? false

        // v2 additive field: default preserves older snapshots.
        let priority = (try? c.decode(Int.self, forKey: .priority)) ?? 0

        let isCompleted = (try? c.decode(Bool.self, forKey: .isCompleted)) ?? false
        let isFlagged = (try? c.decode(Bool.self, forKey: .isFlagged)) ?? false
        let isRecurring = (try? c.decode(Bool.self, forKey: .isRecurring)) ?? false

        let listID = (try? c.decode(String.self, forKey: .listID)) ?? ""
        let listTitle = (try? c.decode(String.self, forKey: .listTitle)) ?? ""

        self.init(
            id: id,
            title: title,
            dueDate: dueDate,
            dueHasTime: dueHasTime,
            startDate: startDate,
            startHasTime: startHasTime,
            priority: priority,
            isCompleted: isCompleted,
            isFlagged: isFlagged,
            isRecurring: isRecurring,
            listID: listID,
            listTitle: listTitle
        )
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(dueDate, forKey: .dueDate)
        try c.encode(dueHasTime, forKey: .dueHasTime)
        try c.encodeIfPresent(startDate, forKey: .startDate)
        try c.encode(startHasTime, forKey: .startHasTime)
        try c.encode(priority, forKey: .priority)
        try c.encode(isCompleted, forKey: .isCompleted)
        try c.encode(isFlagged, forKey: .isFlagged)
        try c.encode(isRecurring, forKey: .isRecurring)
        try c.encode(listID, forKey: .listID)
        try c.encode(listTitle, forKey: .listTitle)
    }
}

/// Optional precomputed grouping for a Reminders mode.
///
/// Notes:
/// - `itemIDs` supports dense/focus presentations.
/// - `sections` supports sectioned presentation.
/// - Both can be filled; renderers can prefer `sections` when non-empty.
public struct WidgetWeaverRemindersModeSnapshot: Codable, Hashable, Identifiable, Sendable {
    public var mode: WidgetWeaverRemindersMode
    public var itemIDs: [String]
    public var sections: [WidgetWeaverRemindersSection]

    public var id: String { mode.rawValue }

    public init(
        mode: WidgetWeaverRemindersMode,
        itemIDs: [String] = [],
        sections: [WidgetWeaverRemindersSection] = []
    ) {
        self.mode = mode
        self.itemIDs = itemIDs
        self.sections = sections

        self = self.normalised()
    }

    public func normalised() -> WidgetWeaverRemindersModeSnapshot {
        var m = self
        m.itemIDs = m.itemIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        m.sections = m.sections.map { $0.normalised() }
        return m
    }

    private enum CodingKeys: String, CodingKey {
        case mode
        case itemIDs
        case sections
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let mode = (try? c.decode(WidgetWeaverRemindersMode.self, forKey: .mode)) ?? .today
        let itemIDs = (try? c.decode([String].self, forKey: .itemIDs)) ?? []
        let sections = (try? c.decode([WidgetWeaverRemindersSection].self, forKey: .sections)) ?? []

        self.init(mode: mode, itemIDs: itemIDs, sections: sections)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(mode, forKey: .mode)
        try c.encode(itemIDs, forKey: .itemIDs)
        try c.encode(sections, forKey: .sections)
    }
}

public struct WidgetWeaverRemindersSection: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var title: String
    public var subtitle: String?
    public var itemIDs: [String]

    public init(
        id: String,
        title: String,
        subtitle: String? = nil,
        itemIDs: [String] = []
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.itemIDs = itemIDs

        self = self.normalised()
    }

    public func normalised() -> WidgetWeaverRemindersSection {
        var s = self

        s.id = s.id.trimmingCharacters(in: .whitespacesAndNewlines)

        let trimmedTitle = s.title.trimmingCharacters(in: .whitespacesAndNewlines)
        s.title = trimmedTitle.isEmpty ? "Untitled" : trimmedTitle

        if let subtitle = s.subtitle {
            let trimmed = subtitle.trimmingCharacters(in: .whitespacesAndNewlines)
            s.subtitle = trimmed.isEmpty ? nil : trimmed
        }

        s.itemIDs = s.itemIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return s
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case title
        case subtitle
        case itemIDs
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let id = (try? c.decode(String.self, forKey: .id)) ?? ""
        let title = (try? c.decode(String.self, forKey: .title)) ?? ""
        let subtitle = try? c.decode(String.self, forKey: .subtitle)
        let itemIDs = (try? c.decode([String].self, forKey: .itemIDs)) ?? []

        self.init(id: id, title: title, subtitle: subtitle, itemIDs: itemIDs)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(id, forKey: .id)
        try c.encode(title, forKey: .title)
        try c.encodeIfPresent(subtitle, forKey: .subtitle)
        try c.encode(itemIDs, forKey: .itemIDs)
    }
}

// MARK: - Diagnostics models

/// Snapshot-level diagnostics for the Reminders engine.
///
/// Used to communicate:
/// - Permission states (denied, restricted, write-only).
/// - Fetch errors / decode errors / unexpected failures.
/// - Success messages (optional).
public struct WidgetWeaverRemindersDiagnostics: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
        case ok
        case notAuthorised
        case writeOnly
        case denied
        case restricted
        case error

        public var id: String { rawValue }
    }

    public var kind: Kind
    public var message: String
    public var at: Date

    public init(kind: Kind, message: String, at: Date = Date()) {
        self.kind = kind
        self.message = message
        self.at = at

        self = self.normalised()
    }

    public func normalised() -> WidgetWeaverRemindersDiagnostics {
        var d = self
        d.message = d.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.message.isEmpty {
            d.message = "Unknown Reminders state."
        }
        return d
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
        case at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let kindRaw = (try? c.decode(String.self, forKey: .kind)) ?? Kind.error.rawValue
        let kind = Kind(rawValue: kindRaw) ?? .error

        let message = (try? c.decode(String.self, forKey: .message)) ?? ""
        let at = (try? c.decode(Date.self, forKey: .at)) ?? Date()

        self.init(kind: kind, message: message, at: at)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(message, forKey: .message)
        try c.encode(at, forKey: .at)
    }
}

/// Last-action diagnostics for widget interactions (complete taps).
public struct WidgetWeaverRemindersActionDiagnostics: Codable, Hashable, Sendable {
    public enum Kind: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
        case none
        case completed
        case error

        public var id: String { rawValue }
    }

    public var kind: Kind
    public var message: String
    public var at: Date

    public init(kind: Kind, message: String, at: Date = Date()) {
        self.kind = kind
        self.message = message
        self.at = at

        self = self.normalised()
    }

    public func normalised() -> WidgetWeaverRemindersActionDiagnostics {
        var d = self
        d.message = d.message.trimmingCharacters(in: .whitespacesAndNewlines)
        if d.message.isEmpty {
            d.message = "No action recorded."
        }
        return d
    }

    private enum CodingKeys: String, CodingKey {
        case kind
        case message
        case at
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let kindRaw = (try? c.decode(String.self, forKey: .kind)) ?? Kind.error.rawValue
        let kind = Kind(rawValue: kindRaw) ?? .error

        let message = (try? c.decode(String.self, forKey: .message)) ?? ""
        let at = (try? c.decode(Date.self, forKey: .at)) ?? Date()

        self.init(kind: kind, message: message, at: at)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(kind, forKey: .kind)
        try c.encode(message, forKey: .message)
        try c.encode(at, forKey: .at)
    }
}

/// A cached snapshot of reminders data for widget rendering.
///
/// Notes:
/// - Widget rendering should only read this snapshot, never query EventKit directly.
/// - `modes` is optional and can be left empty until the engine precomputes per-mode groupings.
public struct WidgetWeaverRemindersSnapshot: Codable, Hashable, Sendable {
    public var generatedAt: Date
    public var items: [WidgetWeaverReminderItem]
    public var modes: [WidgetWeaverRemindersModeSnapshot]

    /// Optional diagnostics captured at snapshot generation time.
    public var diagnostics: WidgetWeaverRemindersDiagnostics?

    public init(
        generatedAt: Date = Date(),
        items: [WidgetWeaverReminderItem] = [],
        modes: [WidgetWeaverRemindersModeSnapshot] = [],
        diagnostics: WidgetWeaverRemindersDiagnostics? = nil
    ) {
        self.generatedAt = generatedAt
        self.items = items
        self.modes = modes
        self.diagnostics = diagnostics

        self = self.normalised()
    }

    public func normalised() -> WidgetWeaverRemindersSnapshot {
        var s = self
        s.items = s.items.map { $0.normalised() }
        s.modes = s.modes.map { $0.normalised() }
        return s
    }

    public var itemsByID: [String: WidgetWeaverReminderItem] {
        Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    public static func sample(now: Date = Date()) -> WidgetWeaverRemindersSnapshot {
        let cal = Calendar.current
        let startOfDay = cal.startOfDay(for: now)

        let listID = "sample.list"
        let listTitle = "Inbox"

        let items: [WidgetWeaverReminderItem] = [
            WidgetWeaverReminderItem(
                id: "sample.1",
                title: "Buy milk",
                dueDate: startOfDay,
                dueHasTime: false,
                isCompleted: false,
                isFlagged: false,
                listID: listID,
                listTitle: listTitle
            ),
            WidgetWeaverReminderItem(
                id: "sample.2",
                title: "Reply to email",
                dueDate: cal.date(byAdding: .hour, value: 2, to: startOfDay),
                dueHasTime: true,
                isCompleted: false,
                isFlagged: true,
                listID: listID,
                listTitle: listTitle
            ),
            WidgetWeaverReminderItem(
                id: "sample.3",
                title: "Book dentist",
                dueDate: cal.date(byAdding: .day, value: 1, to: startOfDay),
                dueHasTime: false,
                isCompleted: false,
                isFlagged: false,
                listID: listID,
                listTitle: listTitle
            ),
        ]

        return WidgetWeaverRemindersSnapshot(
            generatedAt: now,
            items: items,
            modes: [],
            diagnostics: WidgetWeaverRemindersDiagnostics(kind: .ok, message: "Sample snapshot")
        )
    }

    // MARK: Codable compatibility (future-proofing)

    private enum CodingKeys: String, CodingKey {
        case generatedAt
        case items
        case modes
        case diagnostics
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)

        let generatedAt = (try? c.decode(Date.self, forKey: .generatedAt)) ?? Date()
        let items = (try? c.decode([WidgetWeaverReminderItem].self, forKey: .items)) ?? []
        let modes = (try? c.decode([WidgetWeaverRemindersModeSnapshot].self, forKey: .modes)) ?? []
        let diagnostics = try? c.decode(WidgetWeaverRemindersDiagnostics.self, forKey: .diagnostics)

        self.init(generatedAt: generatedAt, items: items, modes: modes, diagnostics: diagnostics)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(generatedAt, forKey: .generatedAt)
        try c.encode(items, forKey: .items)
        try c.encode(modes, forKey: .modes)
        try c.encodeIfPresent(diagnostics, forKey: .diagnostics)
    }
}
