//
//  RemindersSmartStackV2PartitionerTests.swift
//  WidgetWeaver
//
//  Created by . . on 1/29/26.
//

import Foundation
import Testing
@testable import WidgetWeaver

struct RemindersSmartStackV2PartitionerTests {

    private func makeCalendarUTC() -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(secondsFromGMT: 0)!
        cal.locale = Locale(identifier: "en_GB")
        return cal
    }

    private func makeDate(
        _ year: Int,
        _ month: Int,
        _ day: Int,
        _ hour: Int = 0,
        _ minute: Int = 0,
        calendar: Calendar
    ) -> Date {
        let comps = DateComponents(
            calendar: calendar,
            timeZone: calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour,
            minute: minute
        )
        return calendar.date(from: comps)!
    }

    @Test func partition_dedupesAcrossBuckets_withFirstMatchPrecedence() {
        let cal = makeCalendarUTC()
        let now = makeDate(2026, 1, 29, 12, 0, calendar: cal)

        let listA = (id: "list.a", title: "Inbox")
        let listB = (id: "list.b", title: "Work")

        let items: [WidgetWeaverReminderItem] = [
            // Overdue
            WidgetWeaverReminderItem(
                id: "r.overdue.date",
                title: "Overdue date-only",
                dueDate: makeDate(2026, 1, 28, 0, 0, calendar: cal),
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: listA.id,
                listTitle: listA.title
            ),

            // Today + high priority overlap -> Today only
            WidgetWeaverReminderItem(
                id: "r.today.high",
                title: "Due today high priority",
                dueDate: makeDate(2026, 1, 29, 13, 0, calendar: cal),
                dueHasTime: true,
                priority: 1,
                isCompleted: false,
                isFlagged: true,
                listID: listA.id,
                listTitle: listA.title
            ),

            // Due tomorrow + high priority overlap -> Upcoming only
            WidgetWeaverReminderItem(
                id: "r.tomorrow.high",
                title: "Due tomorrow high priority",
                dueDate: makeDate(2026, 1, 30, 10, 0, calendar: cal),
                dueHasTime: true,
                priority: 1,
                isCompleted: false,
                isFlagged: true,
                listID: listA.id,
                listTitle: listA.title
            ),

            // High priority with no due date -> High priority only
            WidgetWeaverReminderItem(
                id: "r.nodue.high",
                title: "No due high priority",
                dueDate: nil,
                dueHasTime: false,
                priority: 2,
                isCompleted: false,
                isFlagged: true,
                listID: listB.id,
                listTitle: listB.title
            ),

            // Anytime
            WidgetWeaverReminderItem(
                id: "r.anytime",
                title: "No due anytime",
                dueDate: nil,
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: listB.id,
                listTitle: listB.title
            ),

            // Lists remainder (due beyond upcoming window, not high priority)
            WidgetWeaverReminderItem(
                id: "r.lists.future",
                title: "Future low priority",
                dueDate: makeDate(2026, 2, 10, 0, 0, calendar: cal),
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: listA.id,
                listTitle: listA.title
            ),
        ]

        let p = WidgetWeaverRemindersSmartStackV2Partitioner.partition(items: items, now: now, calendar: cal)

        let overdueIDs = Set(p.overdue.map { $0.id })
        let todayIDs = Set(p.today.map { $0.id })
        let upcomingIDs = Set(p.upcoming.map { $0.id })
        let highPriorityIDs = Set(p.highPriority.map { $0.id })
        let anytimeIDs = Set(p.anytime.map { $0.id })
        let listsIDs = Set(p.lists.flatMap { $0.itemIDs })

        let all: [Set<String>] = [overdueIDs, todayIDs, upcomingIDs, highPriorityIDs, anytimeIDs, listsIDs]
        let union = all.reduce(into: Set<String>()) { $0.formUnion($1) }

        #expect(union.count == items.count)

        for i in 0..<all.count {
            for j in (i + 1)..<all.count {
                #expect(all[i].intersection(all[j]).isEmpty)
            }
        }

        #expect(todayIDs.contains("r.today.high"))
        #expect(!highPriorityIDs.contains("r.today.high"))

        #expect(upcomingIDs.contains("r.tomorrow.high"))
        #expect(!highPriorityIDs.contains("r.tomorrow.high"))

        #expect(highPriorityIDs.contains("r.nodue.high"))
        #expect(!anytimeIDs.contains("r.nodue.high"))

        #expect(listsIDs.contains("r.lists.future"))
        #expect(!overdueIDs.contains("r.lists.future"))
        #expect(!todayIDs.contains("r.lists.future"))
        #expect(!upcomingIDs.contains("r.lists.future"))
        #expect(!highPriorityIDs.contains("r.lists.future"))
        #expect(!anytimeIDs.contains("r.lists.future"))
    }

    @Test func partition_todaySortsTimedBeforeDateOnly() {
        let cal = makeCalendarUTC()
        let now = makeDate(2026, 1, 29, 12, 0, calendar: cal)

        let list = (id: "list.a", title: "Inbox")

        let items: [WidgetWeaverReminderItem] = [
            WidgetWeaverReminderItem(
                id: "r.today.date",
                title: "Date-only",
                dueDate: makeDate(2026, 1, 29, 0, 0, calendar: cal),
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
            WidgetWeaverReminderItem(
                id: "r.today.early",
                title: "Timed early",
                dueDate: makeDate(2026, 1, 29, 9, 0, calendar: cal),
                dueHasTime: true,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
            WidgetWeaverReminderItem(
                id: "r.today.late",
                title: "Timed late",
                dueDate: makeDate(2026, 1, 29, 18, 0, calendar: cal),
                dueHasTime: true,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
        ]

        let p = WidgetWeaverRemindersSmartStackV2Partitioner.partition(items: items, now: now, calendar: cal)
        let ids = p.today.map { $0.id }

        #expect(ids.count == 3)
        #expect(ids[0] == "r.today.early")
        #expect(ids[1] == "r.today.late")
        #expect(ids[2] == "r.today.date")
    }

    @Test func partition_overdueIsDayBased_notTimeBasedWithinToday() {
        let cal = makeCalendarUTC()
        let now = makeDate(2026, 1, 29, 12, 0, calendar: cal)

        let list = (id: "list.a", title: "Inbox")

        let items: [WidgetWeaverReminderItem] = [
            WidgetWeaverReminderItem(
                id: "r.today.past.time",
                title: "Timed earlier today",
                dueDate: makeDate(2026, 1, 29, 1, 0, calendar: cal),
                dueHasTime: true,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
            WidgetWeaverReminderItem(
                id: "r.yesterday.time",
                title: "Timed yesterday",
                dueDate: makeDate(2026, 1, 28, 23, 0, calendar: cal),
                dueHasTime: true,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
        ]

        let p = WidgetWeaverRemindersSmartStackV2Partitioner.partition(items: items, now: now, calendar: cal)

        let overdueIDs = Set(p.overdue.map { $0.id })
        let todayIDs = Set(p.today.map { $0.id })

        #expect(todayIDs.contains("r.today.past.time"))
        #expect(!overdueIDs.contains("r.today.past.time"))

        #expect(overdueIDs.contains("r.yesterday.time"))
        #expect(!todayIDs.contains("r.yesterday.time"))
    }

    @Test func partition_upcomingWindow_edgesTomorrowAndDayPlus7Inclusive() {
        let cal = makeCalendarUTC()
        let now = makeDate(2026, 1, 29, 12, 0, calendar: cal)

        let list = (id: "list.a", title: "Inbox")

        let items: [WidgetWeaverReminderItem] = [
            WidgetWeaverReminderItem(
                id: "r.tomorrow.start",
                title: "Tomorrow",
                dueDate: makeDate(2026, 1, 30, 0, 0, calendar: cal),
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
            WidgetWeaverReminderItem(
                id: "r.day7",
                title: "Day+7",
                dueDate: makeDate(2026, 2, 5, 23, 59, calendar: cal),
                dueHasTime: true,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
            WidgetWeaverReminderItem(
                id: "r.day8.start",
                title: "Day+8 start",
                dueDate: makeDate(2026, 2, 6, 0, 0, calendar: cal),
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
        ]

        let p = WidgetWeaverRemindersSmartStackV2Partitioner.partition(items: items, now: now, calendar: cal)
        let upcomingIDs = Set(p.upcoming.map { $0.id })
        let listsIDs = Set(p.lists.flatMap { $0.itemIDs })

        #expect(upcomingIDs.contains("r.tomorrow.start"))
        #expect(upcomingIDs.contains("r.day7"))

        #expect(!upcomingIDs.contains("r.day8.start"))
        #expect(listsIDs.contains("r.day8.start"))
    }

    @Test func partition_missingDueDateTreatsAsNoDueDate() {
        let cal = makeCalendarUTC()
        let now = makeDate(2026, 1, 29, 12, 0, calendar: cal)

        let list = (id: "list.a", title: "Inbox")

        let items: [WidgetWeaverReminderItem] = [
            WidgetWeaverReminderItem(
                id: "r.invalidDue.high",
                title: "Invalid due high priority",
                dueDate: nil,
                dueHasTime: true,
                priority: 1,
                isCompleted: false,
                isFlagged: true,
                listID: list.id,
                listTitle: list.title
            ),
            WidgetWeaverReminderItem(
                id: "r.invalidDue.low",
                title: "Invalid due low priority",
                dueDate: nil,
                dueHasTime: true,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                listID: list.id,
                listTitle: list.title
            ),
        ]

        let p = WidgetWeaverRemindersSmartStackV2Partitioner.partition(items: items, now: now, calendar: cal)

        let highPriorityIDs = Set(p.highPriority.map { $0.id })
        let anytimeIDs = Set(p.anytime.map { $0.id })

        #expect(highPriorityIDs.contains("r.invalidDue.high"))
        #expect(!anytimeIDs.contains("r.invalidDue.high"))

        #expect(anytimeIDs.contains("r.invalidDue.low"))
        #expect(!highPriorityIDs.contains("r.invalidDue.low"))
    }

    @Test func partition_recurringOverdueIsCarryOverForToday_notOverdue() {
        let cal = makeCalendarUTC()
        let now = makeDate(2026, 1, 29, 12, 0, calendar: cal)

        let list = (id: "list.a", title: "Inbox")

        let items: [WidgetWeaverReminderItem] = [
            WidgetWeaverReminderItem(
                id: "r.recurring.carry",
                title: "Recurring carry-over",
                dueDate: makeDate(2026, 1, 28, 0, 0, calendar: cal),
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                isRecurring: true,
                listID: list.id,
                listTitle: list.title
            ),
            WidgetWeaverReminderItem(
                id: "r.overdue.oneoff",
                title: "Overdue one-off",
                dueDate: makeDate(2026, 1, 28, 0, 0, calendar: cal),
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                isRecurring: false,
                listID: list.id,
                listTitle: list.title
            ),
            WidgetWeaverReminderItem(
                id: "r.today.date",
                title: "Due today",
                dueDate: makeDate(2026, 1, 29, 0, 0, calendar: cal),
                dueHasTime: false,
                priority: 0,
                isCompleted: false,
                isFlagged: false,
                isRecurring: false,
                listID: list.id,
                listTitle: list.title
            ),
        ]

        let p = WidgetWeaverRemindersSmartStackV2Partitioner.partition(items: items, now: now, calendar: cal)

        let overdueIDs = Set(p.overdue.map { $0.id })
        let todayIDs = Set(p.today.map { $0.id })

        #expect(todayIDs.contains("r.recurring.carry"))
        #expect(!overdueIDs.contains("r.recurring.carry"))

        #expect(overdueIDs.contains("r.overdue.oneoff"))
        #expect(!todayIDs.contains("r.overdue.oneoff"))

        #expect(todayIDs.contains("r.today.date"))

        #expect(p.today.count == 2)
        #expect(p.today.first?.id == "r.recurring.carry")
    }
}
