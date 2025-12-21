//
//  WidgetWeaverSteps.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//
//  Shared Steps models + storage.
//

import Foundation

// MARK: - Snapshot models

public struct WidgetWeaverStepsSnapshot: Codable, Hashable, Sendable {
    public var fetchedAt: Date
    public var startOfDay: Date
    public var steps: Int

    public init(fetchedAt: Date, startOfDay: Date, steps: Int) {
        self.fetchedAt = fetchedAt
        self.startOfDay = startOfDay
        self.steps = steps
    }

    public static func sample() -> WidgetWeaverStepsSnapshot {
        let cal = Calendar.autoupdatingCurrent
        let now = Date()
        return WidgetWeaverStepsSnapshot(
            fetchedAt: now,
            startOfDay: cal.startOfDay(for: now),
            steps: 7_532
        )
    }
}

public struct WidgetWeaverStepsDayPoint: Codable, Hashable, Sendable, Identifiable {
    public var dayStart: Date
    public var steps: Int

    public var id: Date { dayStart }

    public init(dayStart: Date, steps: Int) {
        self.dayStart = dayStart
        self.steps = steps
    }
}

public struct WidgetWeaverStepsHistorySnapshot: Codable, Hashable, Sendable {
    public var fetchedAt: Date
    public var earliestDay: Date
    public var latestDay: Date
    public var days: [WidgetWeaverStepsDayPoint]

    public init(fetchedAt: Date, earliestDay: Date, latestDay: Date, days: [WidgetWeaverStepsDayPoint]) {
        self.fetchedAt = fetchedAt
        self.earliestDay = earliestDay
        self.latestDay = latestDay
        self.days = days
    }

    public static func sample() -> WidgetWeaverStepsHistorySnapshot {
        let cal = Calendar.autoupdatingCurrent
        let now = Date()
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -120, to: today) ?? today.addingTimeInterval(-120 * 86_400)

        var points: [WidgetWeaverStepsDayPoint] = []
        points.reserveCapacity(121)
        for i in 0...120 {
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start.addingTimeInterval(Double(i) * 86_400)
            let steps = 2_500 + (i * 35 % 9_000)
            points.append(WidgetWeaverStepsDayPoint(dayStart: cal.startOfDay(for: d), steps: steps))
        }

        return WidgetWeaverStepsHistorySnapshot(
            fetchedAt: now,
            earliestDay: start,
            latestDay: today,
            days: points
        )
    }
}

// MARK: - Access + goals

public enum WidgetWeaverStepsAccess: String, Codable, Hashable, Sendable {
    case unknown
    case notAvailable
    case notDetermined
    case authorised
    case denied
}

public struct WidgetWeaverStepsGoalSchedule: Codable, Hashable, Sendable {
    public var weekdayGoalSteps: Int
    public var weekendGoalSteps: Int

    public init(weekdayGoalSteps: Int, weekendGoalSteps: Int) {
        self.weekdayGoalSteps = Self.clampGoal(weekdayGoalSteps)
        self.weekendGoalSteps = Self.clampGoal(weekendGoalSteps)
    }

    public static func clampGoal(_ v: Int) -> Int {
        if v < 0 { return 0 }
        if v > 200_000 { return 200_000 }
        return v
    }

    public func goalSteps(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let weekday = calendar.component(.weekday, from: date)
        let isWeekend = weekday == 1 || weekday == 7
        return isWeekend ? weekendGoalSteps : weekdayGoalSteps
    }
}

public enum WidgetWeaverStepsStreakRule: String, Codable, Hashable, Sendable, CaseIterable, Identifiable {
    case strict
    case completeDaysOnly

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .strict: return "Strict"
        case .completeDaysOnly: return "Fair"
        }
    }

    public var helpText: String {
        switch self {
        case .strict:
            return "Strict counts today. If today is below goal so far, the streak is 0."
        case .completeDaysOnly:
            return "Fair doesn’t count today until it’s complete. If today is below goal so far, it doesn’t break the streak."
        }
    }
}

// MARK: - Store

public final class WidgetWeaverStepsStore: @unchecked Sendable {
    public static let shared = WidgetWeaverStepsStore()

    public enum Keys {
        public static let snapshotData = "ww.steps.snapshot.data"
        public static let snapshotStartOfDay = "ww.steps.snapshot.startOfDay"
        public static let lastAccess = "ww.steps.lastAccess"
        public static let lastError = "ww.steps.lastError"

        public static let goalSteps = "ww.steps.goalSteps" // legacy single goal
        public static let weekdayGoalSteps = "ww.steps.goalSteps.weekday"
        public static let weekendGoalSteps = "ww.steps.goalSteps.weekend"
        public static let streakRule = "ww.steps.streakRule"

        public static let historyData = "ww.steps.history.data"
    }

    private let defaults = AppGroup.userDefaults
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    private init() {
        migrateGoalScheduleIfNeeded()
    }

    public func sync() {
        defaults.synchronize()
    }

    public func saveSnapshot(_ snap: WidgetWeaverStepsSnapshot) {
        do {
            let data = try encoder.encode(snap)
            defaults.set(data, forKey: Keys.snapshotData)
            defaults.set(snap.startOfDay, forKey: Keys.snapshotStartOfDay)
            sync()
        } catch {
            defaults.set("Failed to encode snapshot: \(error.localizedDescription)", forKey: Keys.lastError)
        }
    }

    public func snapshotForToday(now: Date = Date()) -> WidgetWeaverStepsSnapshot? {
        guard let data = defaults.data(forKey: Keys.snapshotData) else { return nil }
        guard let snap = try? decoder.decode(WidgetWeaverStepsSnapshot.self, from: data) else { return nil }
        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)
        guard cal.isDate(snap.startOfDay, inSameDayAs: today) else { return nil }
        return snap
    }

    public func saveHistory(_ history: WidgetWeaverStepsHistorySnapshot) {
        do {
            let data = try encoder.encode(history)
            defaults.set(data, forKey: Keys.historyData)
            sync()
        } catch {
            defaults.set("Failed to encode history: \(error.localizedDescription)", forKey: Keys.lastError)
        }
    }

    public func loadHistory() -> WidgetWeaverStepsHistorySnapshot? {
        guard let data = defaults.data(forKey: Keys.historyData) else { return nil }
        return try? decoder.decode(WidgetWeaverStepsHistorySnapshot.self, from: data)
    }

    public func saveLastAccess(_ access: WidgetWeaverStepsAccess) {
        defaults.set(access.rawValue, forKey: Keys.lastAccess)
        sync()
    }

    public func loadLastAccess() -> WidgetWeaverStepsAccess {
        let raw = defaults.string(forKey: Keys.lastAccess) ?? WidgetWeaverStepsAccess.unknown.rawValue
        return WidgetWeaverStepsAccess(rawValue: raw) ?? .unknown
    }

    public func saveLastError(_ message: String?) {
        if let message, !message.isEmpty {
            defaults.set(message, forKey: Keys.lastError)
        } else {
            defaults.removeObject(forKey: Keys.lastError)
        }
        sync()
    }

    public func loadLastError() -> String? {
        defaults.string(forKey: Keys.lastError)
    }

    public func saveGoalSchedule(_ schedule: WidgetWeaverStepsGoalSchedule, writeLegacyKey: Bool) {
        defaults.set(schedule.weekdayGoalSteps, forKey: Keys.weekdayGoalSteps)
        defaults.set(schedule.weekendGoalSteps, forKey: Keys.weekendGoalSteps)

        if writeLegacyKey {
            let maxGoal = max(schedule.weekdayGoalSteps, schedule.weekendGoalSteps)
            defaults.set(maxGoal, forKey: Keys.goalSteps)
            UserDefaults.standard.set(maxGoal, forKey: Keys.goalSteps)
        }

        UserDefaults.standard.set(schedule.weekdayGoalSteps, forKey: Keys.weekdayGoalSteps)
        UserDefaults.standard.set(schedule.weekendGoalSteps, forKey: Keys.weekendGoalSteps)

        sync()
    }

    public func loadGoalSchedule() -> WidgetWeaverStepsGoalSchedule {
        migrateGoalScheduleIfNeeded()

        let weekday = defaults.integer(forKey: Keys.weekdayGoalSteps)
        let weekend = defaults.integer(forKey: Keys.weekendGoalSteps)

        let weekdayValue = (defaults.object(forKey: Keys.weekdayGoalSteps) != nil) ? weekday : 10_000
        let weekendValue = (defaults.object(forKey: Keys.weekendGoalSteps) != nil) ? weekend : 10_000

        return WidgetWeaverStepsGoalSchedule(weekdayGoalSteps: weekdayValue, weekendGoalSteps: weekendValue)
    }

    public func saveStreakRule(_ rule: WidgetWeaverStepsStreakRule) {
        defaults.set(rule.rawValue, forKey: Keys.streakRule)
        UserDefaults.standard.set(rule.rawValue, forKey: Keys.streakRule)
        sync()
    }

    public func loadStreakRule() -> WidgetWeaverStepsStreakRule {
        let raw = defaults.string(forKey: Keys.streakRule)
            ?? UserDefaults.standard.string(forKey: Keys.streakRule)
            ?? WidgetWeaverStepsStreakRule.completeDaysOnly.rawValue
        let rule = WidgetWeaverStepsStreakRule(rawValue: raw) ?? .completeDaysOnly
        defaults.set(rule.rawValue, forKey: Keys.streakRule)
        return rule
    }

    // MARK: - Variable templates

    public func variablesDictionary(now: Date = Date()) -> [String: String] {
        var vars: [String: String] = [:]
        vars.reserveCapacity(64)

        migrateGoalScheduleIfNeeded()

        let schedule = loadGoalSchedule()
        let rule = loadStreakRule()

        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)

        let goalToday = schedule.goalSteps(for: today, calendar: cal)
        vars["__steps_goal_today"] = String(goalToday)
        vars["__steps_goal_weekday"] = String(schedule.weekdayGoalSteps)
        vars["__steps_goal_weekend"] = String(schedule.weekendGoalSteps)

        if let snap = snapshotForToday(now: now) {
            vars["__steps_today"] = String(snap.steps)
            vars["__steps_updated_iso"] = WidgetWeaverVariableTemplate.iso8601String(snap.fetchedAt)

            if goalToday > 0 {
                let fraction = min(1.0, max(0.0, Double(snap.steps) / Double(goalToday)))
                vars["__steps_today_fraction"] = String(fraction)
                vars["__steps_today_percent"] = String(Int((fraction * 100.0).rounded()))
                vars["__steps_goal_hit_today"] = (snap.steps >= goalToday) ? "1" : "0"
            } else {
                vars["__steps_today_fraction"] = "0"
                vars["__steps_today_percent"] = "0"
                vars["__steps_goal_hit_today"] = "0"
            }
        }

        if let history = loadHistory() {
            let analytics = WidgetWeaverStepsAnalytics(history: history, schedule: schedule, streakRule: rule, now: now)

            vars["__steps_streak"] = String(analytics.currentStreakDays)

            let avg7 = analytics.averageSteps(days: 7)
            vars["__steps_avg_7"] = String(Int(avg7.rounded()))
            vars["__steps_avg_7_exact"] = String(avg7)

            let avg30 = analytics.averageSteps(days: 30)
            vars["__steps_avg_30"] = String(Int(avg30.rounded()))
            vars["__steps_avg_30_exact"] = String(avg30)

            if let best = analytics.bestDay {
                vars["__steps_best_day"] = String(best.steps)
                vars["__steps_best_day_date_iso"] = WidgetWeaverVariableTemplate.iso8601String(best.dayStart)
                vars["__steps_best_day_date"] = localDayString(best.dayStart)
            }
        }

        vars["__steps_access"] = loadLastAccess().rawValue
        return vars
    }

    private func localDayString(_ date: Date) -> String {
        let cal = Calendar.autoupdatingCurrent
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = cal.timeZone
        df.dateFormat = "yyyy-MM-dd"
        return df.string(from: date)
    }

    private func migrateGoalScheduleIfNeeded() {
        let weekdayPresent = defaults.object(forKey: Keys.weekdayGoalSteps) != nil
            || UserDefaults.standard.object(forKey: Keys.weekdayGoalSteps) != nil
        let weekendPresent = defaults.object(forKey: Keys.weekendGoalSteps) != nil
            || UserDefaults.standard.object(forKey: Keys.weekendGoalSteps) != nil

        guard !weekdayPresent || !weekendPresent else { return }

        let legacy = loadIntPresence(key: Keys.goalSteps)
        guard legacy.present else { return }

        let g = WidgetWeaverStepsGoalSchedule.clampGoal(legacy.value)
        if !weekdayPresent { setInt(g, key: Keys.weekdayGoalSteps, toStandard: true) }
        if !weekendPresent { setInt(g, key: Keys.weekendGoalSteps, toStandard: true) }
        sync()
    }

    private struct PresenceInt {
        var present: Bool
        var value: Int
    }

    private func loadIntPresence(key: String) -> PresenceInt {
        if defaults.object(forKey: key) != nil {
            return PresenceInt(present: true, value: defaults.integer(forKey: key))
        }
        if UserDefaults.standard.object(forKey: key) != nil {
            let v = UserDefaults.standard.integer(forKey: key)
            defaults.set(v, forKey: key)
            sync()
            return PresenceInt(present: true, value: v)
        }
        return PresenceInt(present: false, value: 0)
    }

    private func setInt(_ value: Int, key: String, toStandard: Bool) {
        defaults.set(value, forKey: key)
        if toStandard {
            UserDefaults.standard.set(value, forKey: key)
        }
    }
}

// MARK: - Modularised files

// WidgetWeaverStepsAnalytics and WidgetWeaverStepsEngine live in separate files to keep
// this file focused on snapshot models, goal schedule, streak rules, and storage.
