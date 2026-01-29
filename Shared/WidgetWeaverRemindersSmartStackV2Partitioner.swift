//
//  WidgetWeaverRemindersSmartStackV2Partitioner.swift
//  WidgetWeaver
//
//  Created by . . on 1/29/26.
//

import Foundation

/// Partitions one snapshot of reminders into the six Smart Stack v2 pages.
///
/// Contract:
/// - Non-overlapping buckets (deduped by stable reminder ID; first-match wins by page order).
/// - Deterministic ordering inside each bucket with a final tie-break by reminder ID.
/// - Day-boundary comparisons are local-calendar-day based (start-of-day anchored).
public enum WidgetWeaverRemindersSmartStackV2Partitioner {

    public struct Partition: Sendable, Hashable {
        public var overdue: [WidgetWeaverReminderItem]
        public var today: [WidgetWeaverReminderItem]
        public var upcoming: [WidgetWeaverReminderItem]
        public var highPriority: [WidgetWeaverReminderItem]
        public var anytime: [WidgetWeaverReminderItem]
        public var lists: [WidgetWeaverRemindersSection]

        public init(
            overdue: [WidgetWeaverReminderItem],
            today: [WidgetWeaverReminderItem],
            upcoming: [WidgetWeaverReminderItem],
            highPriority: [WidgetWeaverReminderItem],
            anytime: [WidgetWeaverReminderItem],
            lists: [WidgetWeaverRemindersSection]
        ) {
            self.overdue = overdue
            self.today = today
            self.upcoming = upcoming
            self.highPriority = highPriority
            self.anytime = anytime
            self.lists = lists
        }

        public static var empty: Partition {
            Partition(overdue: [], today: [], upcoming: [], highPriority: [], anytime: [], lists: [])
        }
    }

    public static func partition(
        items: [WidgetWeaverReminderItem],
        now: Date,
        calendar: Calendar = .autoupdatingCurrent
    ) -> Partition {
        let cal = calendar

        let startOfToday = cal.startOfDay(for: now)
        guard let startOfTomorrow = cal.date(byAdding: .day, value: 1, to: startOfToday),
              let startOfDayPlus8 = cal.date(byAdding: .day, value: 8, to: startOfToday)
        else {
            return .empty
        }

        var assignedIDs: Set<String> = []

        func isAssigned(_ item: WidgetWeaverReminderItem) -> Bool {
            assignedIDs.contains(item.id)
        }

        func markAssigned(_ bucket: [WidgetWeaverReminderItem]) {
            for item in bucket {
                assignedIDs.insert(item.id)
            }
        }

        func prioritySortValue(_ item: WidgetWeaverReminderItem) -> Int {
            let p = item.priority
            if p >= 1 { return p }
            if item.isFlagged { return 1 }
            return Int.max
        }

        func isHighPriority(_ item: WidgetWeaverReminderItem) -> Bool {
            let p = item.priority
            if p >= 1, p <= 4 { return true }
            return p <= 0 && item.isFlagged
        }

        func isOverdue(_ item: WidgetWeaverReminderItem) -> Bool {
            guard let due = item.dueDate else { return false }
            let dueDay = cal.startOfDay(for: due)
            return dueDay < startOfToday
        }

        func isToday(_ item: WidgetWeaverReminderItem) -> Bool {
            guard let due = item.dueDate else { return false }
            return due >= startOfToday && due < startOfTomorrow
        }

        func isUpcoming(_ item: WidgetWeaverReminderItem) -> Bool {
            guard let due = item.dueDate else { return false }
            return due >= startOfTomorrow && due < startOfDayPlus8
        }

        func compareTitle(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let c = a.title.localizedCaseInsensitiveCompare(b.title)
            if c != .orderedSame { return c == .orderedAscending }
            return a.id < b.id
        }

        func compareOverdue(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let ad = a.dueDate ?? Date.distantFuture
            let bd = b.dueDate ?? Date.distantFuture
            if ad != bd { return ad < bd }

            let ap = prioritySortValue(a)
            let bp = prioritySortValue(b)
            if ap != bp { return ap < bp }

            let c = a.title.localizedCaseInsensitiveCompare(b.title)
            if c != .orderedSame { return c == .orderedAscending }
            return a.id < b.id
        }

        func compareToday(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            if a.dueHasTime != b.dueHasTime {
                return a.dueHasTime && !b.dueHasTime
            }

            let ad = a.dueDate ?? Date.distantFuture
            let bd = b.dueDate ?? Date.distantFuture
            if a.dueHasTime, b.dueHasTime {
                if ad != bd { return ad < bd }
            }

            if !a.dueHasTime, !b.dueHasTime {
                let ap = prioritySortValue(a)
                let bp = prioritySortValue(b)
                if ap != bp { return ap < bp }
            }

            let c = a.title.localizedCaseInsensitiveCompare(b.title)
            if c != .orderedSame { return c == .orderedAscending }
            return a.id < b.id
        }

        func compareUpcoming(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let ad = a.dueDate ?? Date.distantFuture
            let bd = b.dueDate ?? Date.distantFuture
            if ad != bd { return ad < bd }

            let ap = prioritySortValue(a)
            let bp = prioritySortValue(b)
            if ap != bp { return ap < bp }

            let c = a.title.localizedCaseInsensitiveCompare(b.title)
            if c != .orderedSame { return c == .orderedAscending }
            return a.id < b.id
        }

        func compareHighPriority(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let ap = prioritySortValue(a)
            let bp = prioritySortValue(b)
            if ap != bp { return ap < bp }

            let aHasDue = a.dueDate != nil
            let bHasDue = b.dueDate != nil
            if aHasDue != bHasDue {
                return aHasDue && !bHasDue
            }

            if let ad = a.dueDate, let bd = b.dueDate {
                if ad != bd { return ad < bd }
            }

            let c = a.title.localizedCaseInsensitiveCompare(b.title)
            if c != .orderedSame { return c == .orderedAscending }
            return a.id < b.id
        }

        func compareAnytime(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let ap = prioritySortValue(a)
            let bp = prioritySortValue(b)
            if ap != bp { return ap < bp }
            return compareTitle(a, b)
        }

        func compareListItem(_ a: WidgetWeaverReminderItem, _ b: WidgetWeaverReminderItem) -> Bool {
            let aHasDue = a.dueDate != nil
            let bHasDue = b.dueDate != nil
            if aHasDue != bHasDue {
                return aHasDue && !bHasDue
            }

            if let ad = a.dueDate, let bd = b.dueDate {
                if ad != bd { return ad < bd }
            }

            let ap = prioritySortValue(a)
            let bp = prioritySortValue(b)
            if ap != bp { return ap < bp }

            let c = a.title.localizedCaseInsensitiveCompare(b.title)
            if c != .orderedSame { return c == .orderedAscending }
            return a.id < b.id
        }

        func take(
            predicate: (WidgetWeaverReminderItem) -> Bool,
            sort: (WidgetWeaverReminderItem, WidgetWeaverReminderItem) -> Bool
        ) -> [WidgetWeaverReminderItem] {
            let bucket = items
                .filter { !isAssigned($0) }
                .filter(predicate)
                .sorted(by: sort)

            markAssigned(bucket)
            return bucket
        }

        let overdue = take(predicate: isOverdue, sort: compareOverdue)
        let today = take(predicate: isToday, sort: compareToday)
        let upcoming = take(predicate: isUpcoming, sort: compareUpcoming)
        let highPriority = take(predicate: isHighPriority, sort: compareHighPriority)
        let anytime = take(predicate: { $0.dueDate == nil }, sort: compareAnytime)

        let remainder = items
            .filter { !isAssigned($0) }

        var byListID: [String: [WidgetWeaverReminderItem]] = [:]
        var listTitleByID: [String: String] = [:]

        for item in remainder {
            byListID[item.listID, default: []].append(item)
            if listTitleByID[item.listID] == nil {
                listTitleByID[item.listID] = item.listTitle
            }
        }

        let sortedListIDs = byListID.keys.sorted { a, b in
            let ta = (listTitleByID[a] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let tb = (listTitleByID[b] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)

            let c = ta.localizedCaseInsensitiveCompare(tb)
            if c != .orderedSame { return c == .orderedAscending }
            return a < b
        }

        let sections: [WidgetWeaverRemindersSection] = sortedListIDs.compactMap { listID in
            guard let listItems = byListID[listID], !listItems.isEmpty else { return nil }
            let title = (listTitleByID[listID] ?? "Untitled").trimmingCharacters(in: .whitespacesAndNewlines)
            let sortedItems = listItems.sorted(by: compareListItem)
            let itemIDs = sortedItems.map { $0.id }
            return WidgetWeaverRemindersSection(id: listID, title: title.isEmpty ? "Untitled" : title, subtitle: nil, itemIDs: itemIDs)
        }

        return Partition(
            overdue: overdue,
            today: today,
            upcoming: upcoming,
            highPriority: highPriority,
            anytime: anytime,
            lists: sections
        )
    }
}
