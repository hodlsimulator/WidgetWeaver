//
//  WidgetWeaverSteps.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//
//  Shared Steps models + storage + HealthKit engines.
//

import Foundation

#if canImport(WidgetKit)
import WidgetKit
#endif

#if canImport(HealthKit)
@preconcurrency import HealthKit
#endif

// MARK: - Models

public struct WidgetWeaverStepsSnapshot: Codable, Hashable, Sendable {
    public var fetchedAt: Date
    public var startOfDay: Date
    public var steps: Int

    public init(fetchedAt: Date, startOfDay: Date, steps: Int) {
        self.fetchedAt = fetchedAt
        self.startOfDay = startOfDay
        self.steps = max(0, steps)
    }

    public var stepsToday: Int { steps }

    public static func sample(now: Date = Date(), steps: Int = 7423) -> WidgetWeaverStepsSnapshot {
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
    public var days: [WidgetWeaverStepsDayPoint] // ascending by dayStart

    public init(fetchedAt: Date, earliestDay: Date, latestDay: Date, days: [WidgetWeaverStepsDayPoint]) {
        self.fetchedAt = fetchedAt
        self.earliestDay = earliestDay
        self.latestDay = latestDay
        self.days = days.sorted { $0.dayStart < $1.dayStart }
    }

    public var dayCount: Int { days.count }
}

public enum WidgetWeaverStepsAccess: String, Codable, Sendable {
    case unknown
    case notAvailable
    case notDetermined
    case denied
    case authorised
}

public enum WidgetWeaverStepsError: Error, Hashable, Sendable, LocalizedError {
    case notAvailable
    case notDetermined
    case denied
    case healthKitError(String)

    public var errorDescription: String? {
        switch self {
        case .notAvailable:
            return "Health data is not available on this device."
        case .notDetermined:
            return "Steps access has not been granted yet."
        case .denied:
            return "Steps access is denied."
        case .healthKitError(let message):
            return message
        }
    }
}

// MARK: - Store

public final class WidgetWeaverStepsStore: @unchecked Sendable {
    public static let shared = WidgetWeaverStepsStore()

    public enum Keys {
        public static let goalSteps = "widgetweaver.steps.goalSteps.v1"
        public static let snapshotData = "widgetweaver.steps.snapshot.v1"
        public static let historyData = "widgetweaver.steps.history.v1"
        public static let lastError = "widgetweaver.steps.lastError.v1"
        public static let lastAccess = "widgetweaver.steps.lastAccess.v1"
    }

    private let defaults: UserDefaults
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    @inline(__always)
    private func sync() {
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

    // MARK: Goal

    public func loadGoalSteps(default fallback: Int = 10_000) -> Int {
        sync()

        let v = defaults.integer(forKey: Keys.goalSteps)
        if v > 0 { return v }

        let legacy = UserDefaults.standard.integer(forKey: Keys.goalSteps)
        if legacy > 0 {
            defaults.set(legacy, forKey: Keys.goalSteps)
            sync()
            return legacy
        }

        return fallback
    }

    public func saveGoalSteps(_ steps: Int) {
        let clamped = max(0, steps)
        defaults.set(clamped, forKey: Keys.goalSteps)
        UserDefaults.standard.set(clamped, forKey: Keys.goalSteps)
        sync()
    }

    // MARK: Snapshot

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
        return (cal.startOfDay(for: snap.startOfDay) == today) ? snap : nil
    }

    // MARK: History

    public func loadHistory() -> WidgetWeaverStepsHistorySnapshot? {
        sync()

        if let data = defaults.data(forKey: Keys.historyData),
           let hist = try? decoder.decode(WidgetWeaverStepsHistorySnapshot.self, from: data) {
            return hist
        }

        if let data = UserDefaults.standard.data(forKey: Keys.historyData),
           let hist = try? decoder.decode(WidgetWeaverStepsHistorySnapshot.self, from: data) {
            if let healed = try? encoder.encode(hist) {
                defaults.set(healed, forKey: Keys.historyData)
            }
            sync()
            return hist
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

    public func clearHistory() {
        defaults.removeObject(forKey: Keys.historyData)
        UserDefaults.standard.removeObject(forKey: Keys.historyData)
        sync()
    }

    // MARK: Access + Errors

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
        let msg = defaults.string(forKey: Keys.lastError) ?? UserDefaults.standard.string(forKey: Keys.lastError)
        let trimmed = msg?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty == true) ? nil : trimmed
    }

    public func saveLastError(_ message: String?) {
        let trimmed = message?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty {
            defaults.set(trimmed, forKey: Keys.lastError)
            UserDefaults.standard.set(trimmed, forKey: Keys.lastError)
        } else {
            defaults.removeObject(forKey: Keys.lastError)
            UserDefaults.standard.removeObject(forKey: Keys.lastError)
        }
        sync()
    }

    // MARK: Widget refresh

    public func recommendedRefreshIntervalSeconds() -> TimeInterval {
        60 * 15
    }
}

// MARK: - Analytics (pure)

public struct WidgetWeaverStepsAnalytics: Hashable, Sendable {
    public let history: WidgetWeaverStepsHistorySnapshot
    public let goal: Int
    public let now: Date

    public init(history: WidgetWeaverStepsHistorySnapshot, goal: Int, now: Date = Date()) {
        self.history = history
        self.goal = goal
        self.now = now
    }

    public var bestDay: WidgetWeaverStepsDayPoint? {
        history.days.max(by: { $0.steps < $1.steps })
    }

    public var currentGoalStreakDays: Int {
        guard goal > 0 else { return 0 }

        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)

        var byDay: [Date: Int] = [:]
        byDay.reserveCapacity(history.days.count)
        for p in history.days {
            byDay[cal.startOfDay(for: p.dayStart)] = p.steps
        }

        var streak = 0
        var cursor = today
        while true {
            guard let steps = byDay[cursor] else { break }
            if steps >= goal { streak += 1 } else { break }
            guard let prev = cal.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return streak
    }

    public func averageSteps(days n: Int) -> Double {
        guard n > 0 else { return 0 }
        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -(n - 1), to: today) ?? today

        let slice = history.days.filter { $0.dayStart >= start && $0.dayStart <= today }
        guard !slice.isEmpty else { return 0 }

        let total = slice.reduce(0) { $0 + $1.steps }
        return Double(total) / Double(slice.count)
    }

    public func stepsOnThisDayByYear() -> [(year: Int, steps: Int)] {
        let cal = Calendar.autoupdatingCurrent
        let comps = cal.dateComponents([.month, .day], from: now)
        guard let month = comps.month, let day = comps.day else { return [] }

        var out: [(Int, Int)] = []
        for p in history.days {
            let c = cal.dateComponents([.year, .month, .day], from: p.dayStart)
            guard let y = c.year, c.month == month, c.day == day else { continue }
            out.append((y, p.steps))
        }
        return out.sorted { $0.0 > $1.0 }
    }
}

// MARK: - Engine (HealthKit)

public final class WidgetWeaverStepsEngine: @unchecked Sendable {
    public static let shared = WidgetWeaverStepsEngine()

    private let store: WidgetWeaverStepsStore

    #if canImport(HealthKit)
    private let healthStore: HKHealthStore
    #endif

    private init(store: WidgetWeaverStepsStore = .shared) {
        self.store = store
        #if canImport(HealthKit)
        self.healthStore = HKHealthStore()
        #endif
    }

    public func requestReadAuthorisation() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError(WidgetWeaverStepsError.notAvailable.localizedDescription)
            return false
        }

        guard let stepType = HKObjectType.quantityType(forIdentifier: .stepCount) else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Step Count is not available.")
            return false
        }

        return await withCheckedContinuation { cont in
            healthStore.requestAuthorization(toShare: [], read: [stepType]) { success, error in
                if let error {
                    self.store.saveLastError(error.localizedDescription)
                } else {
                    self.store.saveLastError(nil)
                }
                cont.resume(returning: success)
            }
        }
        #else
        store.saveLastAccess(.notAvailable)
        store.saveLastError(WidgetWeaverStepsError.notAvailable.localizedDescription)
        return false
        #endif
    }

    public func updateIfNeeded(force: Bool, now: Date = Date()) async -> WidgetWeaverStepsSnapshot? {
        #if targetEnvironment(simulator)
        let simulated = WidgetWeaverStepsSnapshot.sample(now: now)
        store.saveSnapshot(simulated)
        store.saveLastAccess(.authorised)
        store.saveLastError(nil)
        return simulated
        #endif

        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError(WidgetWeaverStepsError.notAvailable.localizedDescription)
            return nil
        }

        if !force, let existing = store.snapshotForToday(now: now) {
            let age = now.timeIntervalSince(existing.fetchedAt)
            if age < store.recommendedRefreshIntervalSeconds() {
                return existing
            }
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Step Count is not available.")
            return nil
        }

        // IMPORTANT:
        // authorizationStatus(for:) reports *share/write* permission.
        // For read-only data, HealthKit intentionally does not expose “denied” vs “allowed”.
        // Use request-status to know if we should prompt, then run the query and treat “no data” as 0.
        let req = await requestStatusForRead(stepType: stepType)
        if req == .shouldRequest {
            store.saveLastAccess(.notDetermined)
            store.saveLastError(WidgetWeaverStepsError.notDetermined.localizedDescription)
            return nil
        }

        do {
            let cal = Calendar.autoupdatingCurrent
            let start = cal.startOfDay(for: now)
            let steps = try await fetchStepSum(start: start, end: now, quantityType: stepType)
            let snap = WidgetWeaverStepsSnapshot(fetchedAt: now, startOfDay: start, steps: steps)
            store.saveSnapshot(snap)
            store.saveLastAccess(.authorised)
            store.saveLastError(nil)
            return snap
        } catch {
            let ns = error as NSError
            store.saveLastAccess(.unknown)
            store.saveLastError("\(ns.domain) (\(ns.code)): \(ns.localizedDescription)")
            return store.snapshotForToday(now: now)
        }
        #else
        store.saveLastAccess(.notAvailable)
        store.saveLastError(WidgetWeaverStepsError.notAvailable.localizedDescription)
        return nil
        #endif
    }

    public func updateHistoryFromBeginningIfNeeded(force: Bool, now: Date = Date()) async -> WidgetWeaverStepsHistorySnapshot? {
        #if targetEnvironment(simulator)
        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)
        let start = cal.date(byAdding: .day, value: -365, to: today) ?? today

        var days: [WidgetWeaverStepsDayPoint] = []
        days.reserveCapacity(366)

        for i in 0...365 {
            let d = cal.date(byAdding: .day, value: i, to: start) ?? start
            let base = 3200 + (i % 7) * 900
            let bump = (i % 11 == 0) ? 5500 : 0
            days.append(WidgetWeaverStepsDayPoint(dayStart: cal.startOfDay(for: d), steps: base + bump))
        }

        let hist = WidgetWeaverStepsHistorySnapshot(fetchedAt: now, earliestDay: start, latestDay: today, days: days)
        store.saveHistory(hist)
        store.saveLastError(nil)
        store.saveLastAccess(.authorised)
        return hist
        #endif

        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError(WidgetWeaverStepsError.notAvailable.localizedDescription)
            return nil
        }

        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Step Count is not available.")
            return nil
        }

        let req = await requestStatusForRead(stepType: stepType)
        if req == .shouldRequest {
            store.saveLastAccess(.notDetermined)
            store.saveLastError(WidgetWeaverStepsError.notDetermined.localizedDescription)
            return nil
        }

        let cal = Calendar.autoupdatingCurrent
        let today = cal.startOfDay(for: now)

        if !force, let existing = store.loadHistory() {
            let age = now.timeIntervalSince(existing.fetchedAt)
            if age < (60 * 30), existing.latestDay == today {
                return existing
            }
        }

        do {
            let earliestSample = try await fetchEarliestStepSampleDate(quantityType: stepType)
            let earliestDay = cal.startOfDay(for: earliestSample ?? today)

            if !force, let existing = store.loadHistory(), existing.earliestDay <= earliestDay {
                var merged = existing

                let lastDay = cal.startOfDay(for: merged.latestDay)
                let startForAppend: Date
                if lastDay < today {
                    startForAppend = cal.date(byAdding: .day, value: 1, to: lastDay) ?? today
                } else {
                    startForAppend = today
                }

                let appended = try await fetchDailySteps(
                    startDay: startForAppend,
                    end: now,
                    quantityType: stepType
                )

                var byDay: [Date: Int] = [:]
                byDay.reserveCapacity(merged.days.count + appended.count)

                for p in merged.days { byDay[cal.startOfDay(for: p.dayStart)] = p.steps }
                for p in appended { byDay[cal.startOfDay(for: p.dayStart)] = p.steps }

                let mergedDays = byDay
                    .map { WidgetWeaverStepsDayPoint(dayStart: $0.key, steps: $0.value) }
                    .sorted { $0.dayStart < $1.dayStart }

                merged = WidgetWeaverStepsHistorySnapshot(
                    fetchedAt: now,
                    earliestDay: min(merged.earliestDay, earliestDay),
                    latestDay: today,
                    days: mergedDays
                )

                store.saveHistory(merged)
                store.saveLastAccess(.authorised)
                store.saveLastError(nil)
                return merged
            } else {
                let days = try await fetchDailySteps(startDay: earliestDay, end: now, quantityType: stepType)
                let hist = WidgetWeaverStepsHistorySnapshot(
                    fetchedAt: now,
                    earliestDay: earliestDay,
                    latestDay: today,
                    days: days
                )
                store.saveHistory(hist)
                store.saveLastAccess(.authorised)
                store.saveLastError(nil)
                return hist
            }
        } catch {
            let ns = error as NSError
            store.saveLastAccess(.unknown)
            store.saveLastError("\(ns.domain) (\(ns.code)): \(ns.localizedDescription)")
            return store.loadHistory()
        }
        #else
        store.saveLastAccess(.notAvailable)
        store.saveLastError(WidgetWeaverStepsError.notAvailable.localizedDescription)
        return nil
        #endif
    }

    public func clearCachedHistory() {
        store.clearHistory()
    }

    // MARK: HealthKit helpers

    #if canImport(HealthKit)
    private func requestStatusForRead(stepType: HKObjectType) async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { cont in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: [stepType]) { status, _ in
                cont.resume(returning: status)
            }
        }
    }

    private func isNoDataAvailableError(_ ns: NSError) -> Bool {
        if ns.domain == HKErrorDomain && ns.code == 11 {
            return true
        }
        let d = ns.localizedDescription.lowercased()
        if d.contains("no data available") { return true }
        let r = (ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?.lowercased() ?? ""
        if r.contains("no data available") { return true }
        return false
    }

    private func fetchStepSum(start: Date, end: Date, quantityType: HKQuantityType) async throws -> Int {
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, stats, error in
                if let error = error as NSError? {
                    if self.isNoDataAvailableError(error) {
                        cont.resume(returning: 0)
                        return
                    }
                    cont.resume(throwing: error)
                    return
                }

                let count = stats?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                cont.resume(returning: Int(count.rounded()))
            }

            self.healthStore.execute(query)
        }
    }

    private func fetchEarliestStepSampleDate(quantityType: HKQuantityType) async throws -> Date? {
        return try await withCheckedThrowingContinuation { cont in
            let sort = NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)
            let query = HKSampleQuery(
                sampleType: quantityType,
                predicate: nil,
                limit: 1,
                sortDescriptors: [sort]
            ) { _, samples, error in
                if let error {
                    cont.resume(throwing: error)
                    return
                }
                let sample = samples?.first as? HKQuantitySample
                cont.resume(returning: sample?.startDate)
            }

            self.healthStore.execute(query)
        }
    }

    private func fetchDailySteps(startDay: Date, end: Date, quantityType: HKQuantityType) async throws -> [WidgetWeaverStepsDayPoint] {
        let cal = Calendar.autoupdatingCurrent
        let start = cal.startOfDay(for: startDay)
        let anchor = cal.startOfDay(for: Date(timeIntervalSinceReferenceDate: 0))

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)
        let interval = DateComponents(day: 1)

        return try await withCheckedThrowingContinuation { cont in
            let query = HKStatisticsCollectionQuery(
                quantityType: quantityType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum,
                anchorDate: anchor,
                intervalComponents: interval
            )

            query.initialResultsHandler = { _, collection, error in
                if let error = error as NSError? {
                    if self.isNoDataAvailableError(error) {
                        cont.resume(returning: [])
                        return
                    }
                    cont.resume(throwing: error)
                    return
                }

                guard let collection else {
                    cont.resume(returning: [])
                    return
                }

                var out: [WidgetWeaverStepsDayPoint] = []
                out.reserveCapacity(512)

                collection.enumerateStatistics(from: start, to: end) { stats, _ in
                    let day = cal.startOfDay(for: stats.startDate)
                    let count = stats.sumQuantity()?.doubleValue(for: .count()) ?? 0
                    out.append(WidgetWeaverStepsDayPoint(dayStart: day, steps: Int(count.rounded())))
                }

                out.sort { $0.dayStart < $1.dayStart }
                cont.resume(returning: out)
            }

            self.healthStore.execute(query)
        }
    }
    #endif
}
