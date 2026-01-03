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
        self.steps = max(0, steps)
    }

    public static func sample(now: Date = Date(), steps: Int = 7_423) -> WidgetWeaverStepsSnapshot {
        let cal = Calendar.autoupdatingCurrent
        return WidgetWeaverStepsSnapshot(
            fetchedAt: now,
            startOfDay: cal.startOfDay(for: now),
            steps: steps
        )
    }
}

public struct WidgetWeaverStepsDayPoint: Codable, Hashable, Sendable, Identifiable {
    public var id: Date { dayStart }
    public var dayStart: Date
    public var steps: Int

    public init(dayStart: Date, steps: Int) {
        self.dayStart = dayStart
        self.steps = max(0, steps)
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
        self.days = days.sorted(by: { $0.dayStart < $1.dayStart })
    }

    public var dayCount: Int { days.count }

    public static func sample(now: Date = Date()) -> WidgetWeaverStepsHistorySnapshot {
        let cal = Calendar.autoupdatingCurrent
        let start = cal.date(byAdding: .day, value: -30, to: cal.startOfDay(for: now)) ?? cal.startOfDay(for: now)
        let end = cal.startOfDay(for: now)
        var days: [WidgetWeaverStepsDayPoint] = []
        var d = start
        while d <= end {
            let steps = Int(4_000 + (Double(abs(d.timeIntervalSince1970).truncatingRemainder(dividingBy: 6_000))))
            days.append(WidgetWeaverStepsDayPoint(dayStart: d, steps: steps))
            d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86_400)
        }
        return WidgetWeaverStepsHistorySnapshot(
            fetchedAt: now,
            earliestDay: start,
            latestDay: end,
            days: days
        )
    }
}

// MARK: - Access

public enum WidgetWeaverStepsAccess: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case unknown
    case notAvailable
    case notDetermined
    case authorised
    case denied

    public var id: String { rawValue }
}

// MARK: - Goal schedule + streak rules

public struct WidgetWeaverStepsGoalSchedule: Codable, Hashable, Sendable {
    public var weekdayGoalSteps: Int
    public var weekendGoalSteps: Int

    public init(weekdayGoalSteps: Int, weekendGoalSteps: Int) {
        self.weekdayGoalSteps = Self.clampGoal(weekdayGoalSteps)
        self.weekendGoalSteps = Self.clampGoal(weekendGoalSteps)
    }

    public static func uniform(_ goalSteps: Int) -> WidgetWeaverStepsGoalSchedule {
        let g = clampGoal(goalSteps)
        return WidgetWeaverStepsGoalSchedule(weekdayGoalSteps: g, weekendGoalSteps: g)
    }

    public func goalSteps(for date: Date, calendar: Calendar = .autoupdatingCurrent) -> Int {
        let day = calendar.startOfDay(for: date)
        let isWeekend = calendar.isDateInWeekend(day)
        return isWeekend ? weekendGoalSteps : weekdayGoalSteps
    }

    public static func clampGoal(_ value: Int) -> Int {
        return max(0, min(200_000, value))
    }
}

public enum WidgetWeaverStepsStreakRule: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
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
            return "Counts today. If today isn't at goal yet, the streak looks broken."
        case .completeDaysOnly:
            return "Counts completed days. Today won't break your streak early. Days with a goal of 0 are skipped."
        }
    }
}

// MARK: - Store

public final class WidgetWeaverStepsStore: @unchecked Sendable {
    public static let shared = WidgetWeaverStepsStore()

    public enum Keys {
        public static let goalSteps = "widgetweaver.steps.goalSteps.v1"

        public static let weekdayGoalSteps = "widgetweaver.steps.goalSteps.weekday.v1"
        public static let weekendGoalSteps = "widgetweaver.steps.goalSteps.weekend.v1"
        public static let streakRule = "widgetweaver.steps.streakRule.v1"

        public static let snapshotData = "widgetweaver.steps.snapshot.v1"
        public static let historyData = "widgetweaver.steps.history.v1"
        public static let lastError = "widgetweaver.steps.lastError.v1"
        public static let lastAccess = "widgetweaver.steps.lastAccess.v1"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    @inline(__always) private func sync() {
        defaults.synchronize()
        UserDefaults.standard.synchronize()
    }

    private init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
        migrateFromWWKeysIfNeeded()
        migrateGoalScheduleIfNeeded()
    }

    // MARK: - Goal schedule

    public func loadGoalSteps(default fallback: Int = 10_000, now: Date = Date()) -> Int {
        let schedule = loadGoalSchedule(default: fallback)
        return schedule.goalSteps(for: now)
    }

    public func saveGoalSteps(_ steps: Int) {
        let g = WidgetWeaverStepsGoalSchedule.clampGoal(steps)
        saveGoalSchedule(WidgetWeaverStepsGoalSchedule(weekdayGoalSteps: g, weekendGoalSteps: g), writeLegacyKey: true)
    }

    public func loadGoalSchedule(default fallback: Int = 10_000) -> WidgetWeaverStepsGoalSchedule {
        sync()

        let legacy = loadIntPresence(key: Keys.goalSteps)
        let weekday = loadIntPresence(key: Keys.weekdayGoalSteps)
        let weekend = loadIntPresence(key: Keys.weekendGoalSteps)

        var weekdayValue: Int
        var weekendValue: Int

        if weekday.present {
            weekdayValue = WidgetWeaverStepsGoalSchedule.clampGoal(weekday.value)
        } else if legacy.present {
            weekdayValue = WidgetWeaverStepsGoalSchedule.clampGoal(legacy.value)
        } else {
            weekdayValue = WidgetWeaverStepsGoalSchedule.clampGoal(fallback)
        }

        if weekend.present {
            weekendValue = WidgetWeaverStepsGoalSchedule.clampGoal(weekend.value)
        } else if legacy.present {
            weekendValue = WidgetWeaverStepsGoalSchedule.clampGoal(legacy.value)
        } else if weekday.present || legacy.present {
            weekendValue = weekdayValue
        } else {
            weekendValue = WidgetWeaverStepsGoalSchedule.clampGoal(fallback)
        }

        if !weekday.present {
            setInt(weekdayValue, key: Keys.weekdayGoalSteps, toStandard: true)
        }
        if !weekend.present {
            setInt(weekendValue, key: Keys.weekendGoalSteps, toStandard: true)
        }

        sync()
        return WidgetWeaverStepsGoalSchedule(weekdayGoalSteps: weekdayValue, weekendGoalSteps: weekendValue)
    }

    public func saveGoalSchedule(_ schedule: WidgetWeaverStepsGoalSchedule, writeLegacyKey: Bool = false) {
        setInt(schedule.weekdayGoalSteps, key: Keys.weekdayGoalSteps, toStandard: true)
        setInt(schedule.weekendGoalSteps, key: Keys.weekendGoalSteps, toStandard: true)
        if writeLegacyKey {
            setInt(schedule.weekdayGoalSteps, key: Keys.goalSteps, toStandard: true)
        }
        sync()
    }

    public func goalSteps(for date: Date, default fallback: Int = 10_000) -> Int {
        loadGoalSchedule(default: fallback).goalSteps(for: date)
    }

    // MARK: - Streak rule

    public func loadStreakRule() -> WidgetWeaverStepsStreakRule {
        sync()
        let raw = defaults.string(forKey: Keys.streakRule)
            ?? UserDefaults.standard.string(forKey: Keys.streakRule)
            ?? WidgetWeaverStepsStreakRule.completeDaysOnly.rawValue
        return WidgetWeaverStepsStreakRule(rawValue: raw) ?? .completeDaysOnly
    }

    public func saveStreakRule(_ rule: WidgetWeaverStepsStreakRule) {
        defaults.set(rule.rawValue, forKey: Keys.streakRule)
        UserDefaults.standard.set(rule.rawValue, forKey: Keys.streakRule)
        sync()
    }

    // MARK: - Snapshot (today)

    public func loadSnapshot() -> WidgetWeaverStepsSnapshot? {
        sync()
        if let data = defaults.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverStepsSnapshot.self, from: data) {
            return snap
        }
        if let data = UserDefaults.standard.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverStepsSnapshot.self, from: data) {
            if let healed = try? encoder.encode(snap) {
                defaults.set(healed, forKey: Keys.snapshotData)
            }
            sync()
            return snap
        }
        return nil
    }

    public func saveSnapshot(_ snapshot: WidgetWeaverStepsSnapshot?) {
        if let snapshot, let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: Keys.snapshotData)
            UserDefaults.standard.set(data, forKey: Keys.snapshotData)
        } else {
            defaults.removeObject(forKey: Keys.snapshotData)
            UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        }
        sync()
    }

    public func snapshotForToday(now: Date = Date()) -> WidgetWeaverStepsSnapshot? {
        guard let snap = loadSnapshot() else { return nil }
        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)
        return cal.isDate(snap.startOfDay, inSameDayAs: today) ? snap : nil
    }

    // MARK: - History (daily totals)

    public func loadHistory() -> WidgetWeaverStepsHistorySnapshot? {
        sync()
        if let data = defaults.data(forKey: Keys.historyData),
           let snap = try? decoder.decode(WidgetWeaverStepsHistorySnapshot.self, from: data) {
            return snap
        }
        if let data = UserDefaults.standard.data(forKey: Keys.historyData),
           let snap = try? decoder.decode(WidgetWeaverStepsHistorySnapshot.self, from: data) {
            if let healed = try? encoder.encode(snap) {
                defaults.set(healed, forKey: Keys.historyData)
            }
            sync()
            return snap
        }
        return nil
    }

    public func saveHistory(_ history: WidgetWeaverStepsHistorySnapshot?) {
        if let history, let data = try? encoder.encode(history) {
            defaults.set(data, forKey: Keys.historyData)
            UserDefaults.standard.set(data, forKey: Keys.historyData)
        } else {
            defaults.removeObject(forKey: Keys.historyData)
            UserDefaults.standard.removeObject(forKey: Keys.historyData)
        }
        sync()
    }

    // MARK: - Last access + errors

    public func loadLastAccess() -> WidgetWeaverStepsAccess {
        sync()
        let raw = defaults.string(forKey: Keys.lastAccess)
            ?? UserDefaults.standard.string(forKey: Keys.lastAccess)
            ?? WidgetWeaverStepsAccess.unknown.rawValue
        return WidgetWeaverStepsAccess(rawValue: raw) ?? .unknown
    }

    public func saveLastAccess(_ access: WidgetWeaverStepsAccess) {
        defaults.set(access.rawValue, forKey: Keys.lastAccess)
        UserDefaults.standard.set(access.rawValue, forKey: Keys.lastAccess)
        sync()
    }

    public func loadLastError() -> String? {
        sync()
        if let s = defaults.string(forKey: Keys.lastError) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let s = UserDefaults.standard.string(forKey: Keys.lastError) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                defaults.set(t, forKey: Keys.lastError)
                sync()
                return t
            }
        }
        return nil
    }

    public func saveLastError(_ error: String?) {
        let trimmed = error?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: Keys.lastError)
            UserDefaults.standard.set(trimmed, forKey: Keys.lastError)
        } else {
            defaults.removeObject(forKey: Keys.lastError)
            UserDefaults.standard.removeObject(forKey: Keys.lastError)
        }
        sync()
    }

    public func recommendedRefreshIntervalSeconds() -> TimeInterval {
        60 * 15
    }

    public func variablesDictionary(now: Date = Date()) -> [String: String] {
        let cal = Calendar.autoupdatingCurrent
        let schedule = loadGoalSchedule()
        let rule = loadStreakRule()

        let today = cal.startOfDay(for: now)
        let goalToday = schedule.goalSteps(for: today, calendar: cal)

        var vars: [String: String] = [:]
        vars["__steps_goal_weekday"] = String(schedule.weekdayGoalSteps)
        vars["__steps_goal_weekend"] = String(schedule.weekendGoalSteps)
        vars["__steps_goal_today"] = String(goalToday)
        vars["__steps_streak_rule"] = rule.rawValue

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

    private enum WWKeys {
        static let goalSteps = "ww.steps.goalSteps"
        static let weekdayGoalSteps = "ww.steps.goalSteps.weekday"
        static let weekendGoalSteps = "ww.steps.goalSteps.weekend"
        static let streakRule = "ww.steps.streakRule"
        static let snapshotData = "ww.steps.snapshot.data"
        static let historyData = "ww.steps.history.data"
        static let lastError = "ww.steps.lastError"
        static let lastAccess = "ww.steps.lastAccess"
    }

    private func migrateFromWWKeysIfNeeded() {
        let hasAny =
            defaults.object(forKey: WWKeys.goalSteps) != nil ||
            defaults.object(forKey: WWKeys.weekdayGoalSteps) != nil ||
            defaults.object(forKey: WWKeys.weekendGoalSteps) != nil ||
            defaults.object(forKey: WWKeys.streakRule) != nil ||
            defaults.object(forKey: WWKeys.snapshotData) != nil ||
            defaults.object(forKey: WWKeys.historyData) != nil ||
            defaults.object(forKey: WWKeys.lastError) != nil ||
            defaults.object(forKey: WWKeys.lastAccess) != nil

        guard hasAny else { return }

        if defaults.object(forKey: Keys.goalSteps) == nil, defaults.object(forKey: WWKeys.goalSteps) != nil {
            let v = WidgetWeaverStepsGoalSchedule.clampGoal(defaults.integer(forKey: WWKeys.goalSteps))
            setInt(v, key: Keys.goalSteps, toStandard: true)
        }

        if defaults.object(forKey: Keys.weekdayGoalSteps) == nil, defaults.object(forKey: WWKeys.weekdayGoalSteps) != nil {
            let v = WidgetWeaverStepsGoalSchedule.clampGoal(defaults.integer(forKey: WWKeys.weekdayGoalSteps))
            setInt(v, key: Keys.weekdayGoalSteps, toStandard: true)
        }

        if defaults.object(forKey: Keys.weekendGoalSteps) == nil, defaults.object(forKey: WWKeys.weekendGoalSteps) != nil {
            let v = WidgetWeaverStepsGoalSchedule.clampGoal(defaults.integer(forKey: WWKeys.weekendGoalSteps))
            setInt(v, key: Keys.weekendGoalSteps, toStandard: true)
        }

        if defaults.string(forKey: Keys.streakRule) == nil, let raw = defaults.string(forKey: WWKeys.streakRule) {
            defaults.set(raw, forKey: Keys.streakRule)
            UserDefaults.standard.set(raw, forKey: Keys.streakRule)
        }

        if defaults.string(forKey: Keys.lastAccess) == nil, let raw = defaults.string(forKey: WWKeys.lastAccess) {
            defaults.set(raw, forKey: Keys.lastAccess)
            UserDefaults.standard.set(raw, forKey: Keys.lastAccess)
        }

        if defaults.string(forKey: Keys.lastError) == nil, let raw = defaults.string(forKey: WWKeys.lastError) {
            defaults.set(raw, forKey: Keys.lastError)
            UserDefaults.standard.set(raw, forKey: Keys.lastError)
        }

        if defaults.data(forKey: Keys.snapshotData) == nil, let data = defaults.data(forKey: WWKeys.snapshotData) {
            if let snap = decodeSnapshotFlexible(data), let healed = try? encoder.encode(snap) {
                defaults.set(healed, forKey: Keys.snapshotData)
                UserDefaults.standard.set(healed, forKey: Keys.snapshotData)
            }
        }

        if defaults.data(forKey: Keys.historyData) == nil, let data = defaults.data(forKey: WWKeys.historyData) {
            if let snap = decodeHistoryFlexible(data), let healed = try? encoder.encode(snap) {
                defaults.set(healed, forKey: Keys.historyData)
                UserDefaults.standard.set(healed, forKey: Keys.historyData)
            }
        }

        sync()
    }

    private func decodeSnapshotFlexible(_ data: Data) -> WidgetWeaverStepsSnapshot? {
        if let snap = try? decoder.decode(WidgetWeaverStepsSnapshot.self, from: data) { return snap }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return try? d.decode(WidgetWeaverStepsSnapshot.self, from: data)
    }

    private func decodeHistoryFlexible(_ data: Data) -> WidgetWeaverStepsHistorySnapshot? {
        if let snap = try? decoder.decode(WidgetWeaverStepsHistorySnapshot.self, from: data) { return snap }
        let d = JSONDecoder()
        d.dateDecodingStrategy = .deferredToDate
        return try? d.decode(WidgetWeaverStepsHistorySnapshot.self, from: data)
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
// WidgetWeaverStepsAnalytics and WidgetWeaverStepsEngine live in separate files.


// MARK: - Activity (multi-metric HealthKit snapshot)
//
// Activity is a sibling feature to Steps:
// - Steps stays simple (stepCount only).
// - Activity can request multiple movement types in one HealthKit prompt
//   (steps, flights climbed, walking/running distance, active energy)
//   and exposes __activity_* keys for templates/widgets.

public struct WidgetWeaverActivitySnapshot: Codable, Hashable, Sendable {
    public var fetchedAt: Date
    public var startOfDay: Date

    // Values are optional to support partial authorisation (e.g. Steps allowed, Flights denied).
    public var steps: Int?
    public var flightsClimbed: Int?
    public var distanceWalkingRunningMeters: Double?
    public var activeEnergyBurnedKilocalories: Double?

    public init(
        fetchedAt: Date,
        startOfDay: Date,
        steps: Int?,
        flightsClimbed: Int?,
        distanceWalkingRunningMeters: Double?,
        activeEnergyBurnedKilocalories: Double?
    ) {
        self.fetchedAt = fetchedAt
        self.startOfDay = startOfDay
        self.steps = steps.map { max(0, $0) }
        self.flightsClimbed = flightsClimbed.map { max(0, $0) }
        self.distanceWalkingRunningMeters = distanceWalkingRunningMeters.map { max(0, $0) }
        self.activeEnergyBurnedKilocalories = activeEnergyBurnedKilocalories.map { max(0, $0) }
    }

    public static func sample(now: Date = Date()) -> WidgetWeaverActivitySnapshot {
        let cal = Calendar.autoupdatingCurrent
        return WidgetWeaverActivitySnapshot(
            fetchedAt: now,
            startOfDay: cal.startOfDay(for: now),
            steps: 7_423,
            flightsClimbed: 11,
            distanceWalkingRunningMeters: 5_250,
            activeEnergyBurnedKilocalories: 412
        )
    }
}

public enum WidgetWeaverActivityAccess: String, Codable, CaseIterable, Hashable, Identifiable, Sendable {
    case unknown
    case notAvailable
    case notDetermined
    case authorised
    case denied
    case partial

    public var id: String { rawValue }
}

public final class WidgetWeaverActivityStore: @unchecked Sendable {
    public static let shared = WidgetWeaverActivityStore()

    public enum Keys {
        public static let snapshotData = "widgetweaver.activity.snapshot.v1"
        public static let lastError = "widgetweaver.activity.lastError.v1"
        public static let lastAccess = "widgetweaver.activity.lastAccess.v1"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    @inline(__always) private func sync() {
        defaults.synchronize()
        UserDefaults.standard.synchronize()
    }

    private init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
        self.encoder = JSONEncoder()
        self.decoder = JSONDecoder()
        self.encoder.dateEncodingStrategy = .iso8601
        self.decoder.dateDecodingStrategy = .iso8601
    }

    // MARK: - Snapshot

    public func snapshotForToday(now: Date = Date()) -> WidgetWeaverActivitySnapshot? {
        guard let snap = loadSnapshot() else { return nil }
        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)
        if !cal.isDate(snap.startOfDay, inSameDayAs: today) { return nil }
        return snap
    }

    public func saveSnapshot(_ snapshot: WidgetWeaverActivitySnapshot?) {
        if let snapshot, let data = try? encoder.encode(snapshot) {
            defaults.set(data, forKey: Keys.snapshotData)
            UserDefaults.standard.set(data, forKey: Keys.snapshotData)
        } else {
            defaults.removeObject(forKey: Keys.snapshotData)
            UserDefaults.standard.removeObject(forKey: Keys.snapshotData)
        }
        sync()
    }

    public func loadSnapshot() -> WidgetWeaverActivitySnapshot? {
        sync()

        if let data = defaults.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverActivitySnapshot.self, from: data)
        {
            return snap
        }

        if let data = UserDefaults.standard.data(forKey: Keys.snapshotData),
           let snap = try? decoder.decode(WidgetWeaverActivitySnapshot.self, from: data)
        {
            defaults.set(data, forKey: Keys.snapshotData)
            sync()
            return snap
        }

        return nil
    }

    // MARK: - Last access + errors

    public func loadLastAccess() -> WidgetWeaverActivityAccess {
        sync()
        let raw = defaults.string(forKey: Keys.lastAccess)
            ?? UserDefaults.standard.string(forKey: Keys.lastAccess)
            ?? WidgetWeaverActivityAccess.unknown.rawValue
        return WidgetWeaverActivityAccess(rawValue: raw) ?? .unknown
    }

    public func saveLastAccess(_ access: WidgetWeaverActivityAccess) {
        defaults.set(access.rawValue, forKey: Keys.lastAccess)
        UserDefaults.standard.set(access.rawValue, forKey: Keys.lastAccess)
        sync()
    }

    public func loadLastError() -> String? {
        sync()

        if let s = defaults.string(forKey: Keys.lastError) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty ? nil : t
        }
        if let s = UserDefaults.standard.string(forKey: Keys.lastError) {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if !t.isEmpty {
                defaults.set(t, forKey: Keys.lastError)
                sync()
                return t
            }
        }
        return nil
    }

    public func saveLastError(_ error: String?) {
        let trimmed = error?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: Keys.lastError)
            UserDefaults.standard.set(trimmed, forKey: Keys.lastError)
        } else {
            defaults.removeObject(forKey: Keys.lastError)
            UserDefaults.standard.removeObject(forKey: Keys.lastError)
        }
        sync()
    }

    public func recommendedRefreshIntervalSeconds() -> TimeInterval {
        60 * 15
    }

    // MARK: - Template variables

    public func variablesDictionary(now: Date = Date()) -> [String: String] {
        var vars: [String: String] = [:]
        vars["__activity_access"] = loadLastAccess().rawValue

        guard let snap = snapshotForToday(now: now) else { return vars }

        vars["__activity_updated_iso"] = WidgetWeaverVariableTemplate.iso8601String(snap.fetchedAt)

        if let steps = snap.steps {
            vars["__activity_steps_today"] = String(steps)
        }

        if let flights = snap.flightsClimbed {
            vars["__activity_flights_today"] = String(flights)
        }

        if let meters = snap.distanceWalkingRunningMeters {
            let roundedM = Int(meters.rounded())
            vars["__activity_distance_m"] = String(roundedM)
            vars["__activity_distance_m_exact"] = String(meters)

            let km = meters / 1000.0
            vars["__activity_distance_km"] = String(format: "%.1f", km)
            vars["__activity_distance_km_exact"] = String(km)
        }

        if let kcal = snap.activeEnergyBurnedKilocalories {
            vars["__activity_active_energy_kcal"] = String(Int(kcal.rounded()))
            vars["__activity_active_energy_kcal_exact"] = String(kcal)
        }

        return vars
    }
}
