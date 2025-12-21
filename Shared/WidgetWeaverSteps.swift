//
//  WidgetWeaverSteps.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//
//  Shared Steps models + storage + HealthKit engine.
//

import Foundation
#if canImport(WidgetKit)
import WidgetKit
#endif
#if canImport(HealthKit)
@preconcurrency import HealthKit
#endif

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

// MARK: - Engine

public actor WidgetWeaverStepsEngine {
    public static let shared = WidgetWeaverStepsEngine()

    public struct Result: Sendable {
        public var snapshot: WidgetWeaverStepsSnapshot?
        public var access: WidgetWeaverStepsAccess
        public var errorDescription: String?

        public init(snapshot: WidgetWeaverStepsSnapshot?, access: WidgetWeaverStepsAccess, errorDescription: String?) {
            self.snapshot = snapshot
            self.access = access
            self.errorDescription = errorDescription
        }
    }

    public var minimumUpdateInterval: TimeInterval = 60 * 15

    private var inFlightSnapshot: Task<Result, Never>?
    private var inFlightHistory: Task<WidgetWeaverStepsHistorySnapshot?, Never>?

    // MARK: - Permission (59f13ec pattern)

    public func requestReadAuthorisation() async -> Bool {
        let store = WidgetWeaverStepsStore.shared

        #if !canImport(HealthKit)
        store.saveLastAccess(.notAvailable)
        store.saveLastError("HealthKit unavailable")
        return false
        #else

        #if targetEnvironment(simulator)
        store.saveLastAccess(.authorised)
        store.saveLastError(nil)
        return true
        #else

        guard HKHealthStore.isHealthDataAvailable() else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Health data is not available on this device.")
            return false
        }

        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Step Count is not available.")
            return false
        }

        let healthStore = HKHealthStore()
        return await withCheckedContinuation { cont in
            healthStore.requestAuthorization(toShare: [], read: [stepType]) { success, error in
                if let error {
                    store.saveLastError(error.localizedDescription)
                } else {
                    store.saveLastError(nil)
                }
                cont.resume(returning: success)
            }
        }

        #endif
        #endif
    }

    // MARK: - Public updates

    public func updateIfNeeded(force: Bool = false) async -> Result {
        if let inFlightSnapshot {
            return await inFlightSnapshot.value
        }
        let task = Task { () -> Result in
            await self.updateSnapshot(force: force)
        }
        inFlightSnapshot = task
        let out = await task.value
        inFlightSnapshot = nil
        return out
    }

    public func updateHistoryFromBeginningIfNeeded(force: Bool = false) async -> WidgetWeaverStepsHistorySnapshot? {
        if let inFlightHistory {
            return await inFlightHistory.value
        }
        let task = Task { () -> WidgetWeaverStepsHistorySnapshot? in
            await self.updateHistory(force: force)
        }
        inFlightHistory = task
        let out = await task.value
        inFlightHistory = nil
        return out
    }

    // MARK: - Internals

    private func updateSnapshot(force: Bool) async -> Result {
        let store = WidgetWeaverStepsStore.shared

        #if !canImport(HealthKit)
        store.saveLastAccess(.notAvailable)
        store.saveLastError("HealthKit unavailable")
        return Result(snapshot: store.snapshotForToday(), access: .notAvailable, errorDescription: store.loadLastError())
        #else

        #if targetEnvironment(simulator)
        let snap = WidgetWeaverStepsSnapshot.sample()
        store.saveSnapshot(snap)
        store.saveLastAccess(.authorised)
        store.saveLastError(nil)
        return Result(snapshot: snap, access: .authorised, errorDescription: nil)
        #else

        guard HKHealthStore.isHealthDataAvailable() else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Health data is not available on this device.")
            return Result(snapshot: store.snapshotForToday(), access: .notAvailable, errorDescription: store.loadLastError())
        }

        if !force, let existing = store.snapshotForToday() {
            let age = Date().timeIntervalSince(existing.fetchedAt)
            if age < minimumUpdateInterval {
                store.saveLastError(nil)
                return Result(snapshot: existing, access: store.loadLastAccess(), errorDescription: nil)
            }
        }

        let healthStore = HKHealthStore()
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Step Count is not available.")
            return Result(snapshot: store.snapshotForToday(), access: .notAvailable, errorDescription: store.loadLastError())
        }

        // 59f13ec fix: gate reads behind request-status (prevents com.apple.healthkit Code=5).
        let req = await requestStatusForRead(healthStore: healthStore, stepType: stepType)
        if req == .shouldRequest {
            store.saveLastAccess(.notDetermined)
            store.saveLastError("Steps access isn’t enabled yet. Tap “Request Steps Access”.")
            return Result(snapshot: store.snapshotForToday(), access: .notDetermined, errorDescription: store.loadLastError())
        }

        do {
            let snap = try await fetchStepsForToday(healthStore: healthStore, stepsType: stepType)
            store.saveSnapshot(snap)
            store.saveLastAccess(.authorised)
            store.saveLastError(nil)
            return Result(snapshot: snap, access: .authorised, errorDescription: nil)
        } catch {
            let ns = error as NSError

            if isAuthorisationNotDeterminedError(ns) {
                store.saveLastAccess(.notDetermined)
                store.saveLastError("Steps access isn’t enabled yet. Tap “Request Steps Access”.")
                return Result(snapshot: store.snapshotForToday(), access: .notDetermined, errorDescription: store.loadLastError())
            }

            if isAuthorisationDeniedError(ns) {
                store.saveLastAccess(.denied)
                store.saveLastError("Steps access is denied. Enable it in the Health app (Sharing → Apps → WidgetWeaver).")
                return Result(snapshot: store.snapshotForToday(), access: .denied, errorDescription: store.loadLastError())
            }

            store.saveLastAccess(.unknown)
            store.saveLastError("\(ns.domain) (\(ns.code)): \(ns.localizedDescription)")
            return Result(snapshot: store.snapshotForToday(), access: store.loadLastAccess(), errorDescription: store.loadLastError())
        }

        #endif
        #endif
    }

    private func updateHistory(force: Bool) async -> WidgetWeaverStepsHistorySnapshot? {
        let store = WidgetWeaverStepsStore.shared

        #if !canImport(HealthKit)
        store.saveLastAccess(.notAvailable)
        store.saveLastError("HealthKit unavailable")
        return nil
        #else

        #if targetEnvironment(simulator)
        let sample = WidgetWeaverStepsHistorySnapshot.sample()
        store.saveHistory(sample)
        store.saveLastAccess(.authorised)
        store.saveLastError(nil)
        return sample
        #else

        guard HKHealthStore.isHealthDataAvailable() else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Health data is not available on this device.")
            return nil
        }

        let healthStore = HKHealthStore()
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Step Count is not available.")
            return nil
        }

        let req = await requestStatusForRead(healthStore: healthStore, stepType: stepType)
        if req == .shouldRequest {
            store.saveLastAccess(.notDetermined)
            store.saveLastError("Steps access isn’t enabled yet. Tap “Request Steps Access”.")
            return nil
        }

        let now = Date()
        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)

        if !force, let existing = store.loadHistory() {
            let age = now.timeIntervalSince(existing.fetchedAt)
            if age < minimumUpdateInterval, cal.isDate(existing.latestDay, inSameDayAs: today) {
                store.saveLastError(nil)
                store.saveLastAccess(.authorised)
                return existing
            }
        }

        do {
            let earliest = try await fetchEarliestStepSampleDay(healthStore: healthStore, stepsType: stepType) ?? today
            let start = cal.startOfDay(for: earliest)
            let end = today
            let days = try await fetchDailySteps(healthStore: healthStore, stepsType: stepType, startDay: start, endDay: end)
            let out = WidgetWeaverStepsHistorySnapshot(fetchedAt: now, earliestDay: start, latestDay: end, days: days)
            store.saveHistory(out)
            store.saveLastAccess(.authorised)
            store.saveLastError(nil)
            return out
        } catch {
            let ns = error as NSError

            if isAuthorisationNotDeterminedError(ns) {
                store.saveLastAccess(.notDetermined)
                store.saveLastError("Steps access isn’t enabled yet. Tap “Request Steps Access”.")
                return store.loadHistory()
            }

            if isAuthorisationDeniedError(ns) {
                store.saveLastAccess(.denied)
                store.saveLastError("Steps access is denied. Enable it in the Health app (Sharing → Apps → WidgetWeaver).")
                return store.loadHistory()
            }

            store.saveLastAccess(.unknown)
            store.saveLastError("\(ns.domain) (\(ns.code)): \(ns.localizedDescription)")
            return store.loadHistory()
        }

        #endif
        #endif
    }

    // MARK: - HealthKit helpers

    #if canImport(HealthKit)
    private func requestStatusForRead(healthStore: HKHealthStore, stepType: HKObjectType) async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { cont in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [stepType]) { status, _ in
                cont.resume(returning: status)
            }
        }
    }

    private func isHealthKitDomain(_ domain: String) -> Bool {
        if domain == HKErrorDomain { return true }
        if domain == "com.apple.healthkit" { return true }
        return false
    }

    private func isNoDataAvailableError(_ ns: NSError) -> Bool {
        if isHealthKitDomain(ns.domain) && ns.code == 11 { return true }
        let d = ns.localizedDescription.lowercased()
        if d.contains("no data available") { return true }
        let r = (ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?.lowercased() ?? ""
        if r.contains("no data available") { return true }
        return false
    }

    private func isAuthorisationNotDeterminedError(_ ns: NSError) -> Bool {
        if isHealthKitDomain(ns.domain) && ns.code == 5 { return true }
        let d = ns.localizedDescription.lowercased()
        if d.contains("authorization not determined") { return true }
        if d.contains("authorisation not determined") { return true }
        return false
    }

    private func isAuthorisationDeniedError(_ ns: NSError) -> Bool {
        if isHealthKitDomain(ns.domain) && ns.code == 4 { return true }
        let d = ns.localizedDescription.lowercased()
        if d.contains("authorization denied") { return true }
        if d.contains("authorisation denied") { return true }
        if d.contains("not authorized") { return true }
        if d.contains("not authorised") { return true }
        return false
    }

    private func fetchStepsForToday(healthStore: HKHealthStore, stepsType: HKQuantityType) async throws -> WidgetWeaverStepsSnapshot {
        let cal = Calendar.autoupdatingCurrent
        let now = Date()
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: stepsType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error = error as NSError? {
                    if self.isNoDataAvailableError(error) {
                        let snap = WidgetWeaverStepsSnapshot(fetchedAt: now, startOfDay: start, steps: 0)
                        continuation.resume(returning: snap)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }

                let sum = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                let snap = WidgetWeaverStepsSnapshot(
                    fetchedAt: now,
                    startOfDay: start,
                    steps: Int(sum.rounded())
                )
                continuation.resume(returning: snap)
            }
            healthStore.execute(query)
        }
    }

    private func fetchEarliestStepSampleDay(healthStore: HKHealthStore, stepsType: HKQuantityType) async throws -> Date? {
        return try await withCheckedThrowingContinuation { continuation in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(sampleType: stepsType, predicate: nil, limit: 1, sortDescriptors: [sort]) { _, samples, error in
                if let error = error as NSError? {
                    if self.isNoDataAvailableError(error) {
                        continuation.resume(returning: nil)
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }
                continuation.resume(returning: samples?.first?.startDate)
            }
            healthStore.execute(query)
        }
    }

    private func fetchDailySteps(healthStore: HKHealthStore, stepsType: HKQuantityType, startDay: Date, endDay: Date) async throws -> [WidgetWeaverStepsDayPoint] {
        let cal = Calendar.autoupdatingCurrent

        let start = cal.startOfDay(for: startDay)
        let end = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: endDay)) ?? cal.startOfDay(for: endDay).addingTimeInterval(86_400)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        var interval = DateComponents()
        interval.day = 1

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsCollectionQuery(
                quantityType: stepsType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: start,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, results, error in
                if let error = error as NSError? {
                    if self.isNoDataAvailableError(error) {
                        continuation.resume(returning: [])
                        return
                    }
                    continuation.resume(throwing: error)
                    return
                }

                var out: [WidgetWeaverStepsDayPoint] = []
                out.reserveCapacity(400)

                results?.enumerateStatistics(from: start, to: end) { stat, _ in
                    let dayStart = cal.startOfDay(for: stat.startDate)
                    let sum = stat.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    out.append(WidgetWeaverStepsDayPoint(dayStart: dayStart, steps: Int(sum.rounded())))
                }

                continuation.resume(returning: out.sorted(by: { $0.dayStart < $1.dayStart }))
            }

            healthStore.execute(query)
        }
    }
    #endif
}
