//
//  WidgetWeaverStepsAnalytics.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//
//  Steps analytics (streaks, averages, best day).
//

import Foundation

// MARK: - Analytics

public struct WidgetWeaverStepsAnalytics: Hashable, Sendable {
    public var history: WidgetWeaverStepsHistorySnapshot
    public var schedule: WidgetWeaverStepsGoalSchedule
    public var streakRule: WidgetWeaverStepsStreakRule
    public var now: Date

    public init(
        history: WidgetWeaverStepsHistorySnapshot,
        schedule: WidgetWeaverStepsGoalSchedule,
        streakRule: WidgetWeaverStepsStreakRule,
        now: Date = Date()
    ) {
        self.history = history
        self.schedule = schedule
        self.streakRule = streakRule
        self.now = now
    }

    private var calendar: Calendar { .autoupdatingCurrent }

    private func stepsMap() -> [Date: Int] {
        var dict: [Date: Int] = [:]
        dict.reserveCapacity(history.days.count)
        for p in history.days { dict[p.dayStart] = p.steps }
        return dict
    }

    public var bestDay: WidgetWeaverStepsDayPoint? {
        history.days.max(by: { $0.steps < $1.steps })
    }

    public var currentStreakDays: Int {
        let cal = calendar
        let byDay = stepsMap()
        let today = cal.startOfDay(for: now)

        var cursor = today

        switch streakRule {
        case .strict:
            break
        case .completeDaysOnly:
            let goalToday = schedule.goalSteps(for: today, calendar: cal)
            if goalToday <= 0 {
                cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86_400)
            } else {
                let stepsToday = byDay[today] ?? 0
                if stepsToday < goalToday {
                    cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86_400)
                }
            }
        }

        var streak = 0
        var safety = 0

        while safety < 10_000 {
            safety += 1

            let goal = schedule.goalSteps(for: cursor, calendar: cal)
            if goal <= 0 {
                cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86_400)
                continue
            }

            guard let steps = byDay[cursor] else { break }
            if steps >= goal {
                streak += 1
                cursor = cal.date(byAdding: .day, value: -1, to: cursor) ?? cursor.addingTimeInterval(-86_400)
                continue
            }
            break
        }

        return streak
    }

    public func averageSteps(days: Int) -> Double {
        let cal = calendar
        let n = max(1, days)
        let end = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(n - 1), to: end) ?? end.addingTimeInterval(-Double(n - 1) * 86_400)

        let slice = history.days.filter { $0.dayStart >= start && $0.dayStart <= end }
        guard !slice.isEmpty else { return 0 }
        let total = slice.reduce(0) { $0 + $1.steps }
        return Double(total) / Double(slice.count)
    }
}
