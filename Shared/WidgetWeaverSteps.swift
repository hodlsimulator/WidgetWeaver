//
//  WidgetWeaverSteps.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//
//  Steps snapshot + HealthKit query engine shared by app + widget extension.
//

import Foundation
#if canImport(HealthKit)
@preconcurrency import HealthKit
#endif

public struct WidgetWeaverStepsSnapshot: Codable, Hashable, Sendable {
    public let stepsToday: Int
    public let startOfDay: Date
    public let fetchedAt: Date

    public init(stepsToday: Int, startOfDay: Date, fetchedAt: Date) {
        self.stepsToday = max(0, stepsToday)
        self.startOfDay = startOfDay
        self.fetchedAt = fetchedAt
    }

    public static func sample(now: Date = Date(), steps: Int = 5432) -> WidgetWeaverStepsSnapshot {
        let calendar = Calendar.autoupdatingCurrent
        return WidgetWeaverStepsSnapshot(
            stepsToday: steps,
            startOfDay: calendar.startOfDay(for: now),
            fetchedAt: now
        )
    }
}

public final class WidgetWeaverStepsStore: @unchecked Sendable {
    public static let shared = WidgetWeaverStepsStore()

    public enum Keys {
        public static let snapshotData = "widgetweaver.steps.snapshot.v1"
        public static let goalSteps = "widgetweaver.steps.goal.v1"
    }

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = AppGroup.userDefaults) {
        self.defaults = defaults
    }

    public func loadGoalSteps() -> Int {
        let raw = defaults.integer(forKey: Keys.goalSteps)
        if raw <= 0 { return 10_000 }
        return raw.clamped(to: 500...200_000)
    }

    public func saveGoalSteps(_ goal: Int) {
        defaults.set(goal.clamped(to: 500...200_000), forKey: Keys.goalSteps)
        defaults.synchronize()
    }

    public func loadSnapshot() -> WidgetWeaverStepsSnapshot? {
        guard let data = defaults.data(forKey: Keys.snapshotData) else { return nil }
        do {
            return try JSONDecoder().decode(WidgetWeaverStepsSnapshot.self, from: data)
        } catch {
            return nil
        }
    }

    public func snapshotForToday(now: Date = Date()) -> WidgetWeaverStepsSnapshot? {
        guard let snap = loadSnapshot() else { return nil }
        let calendar = Calendar.autoupdatingCurrent
        let todayStart = calendar.startOfDay(for: now)
        if abs(snap.startOfDay.timeIntervalSince(todayStart)) > 1 {
            return nil
        }
        return snap
    }

    public func saveSnapshot(_ snapshot: WidgetWeaverStepsSnapshot?) {
        if let snapshot {
            do {
                let data = try JSONEncoder().encode(snapshot)
                defaults.set(data, forKey: Keys.snapshotData)
            } catch {
                return
            }
        } else {
            defaults.removeObject(forKey: Keys.snapshotData)
        }
        defaults.synchronize()
    }

    public func clearSnapshot() {
        saveSnapshot(nil)
    }

    public func recommendedRefreshIntervalSeconds() -> TimeInterval {
        15 * 60
    }
}

public enum WidgetWeaverStepsAuthorisationStatus: Sendable, Equatable {
    case unavailable
    case notDetermined
    case denied
    case authorised
}

public struct WidgetWeaverStepsReadProbe: Sendable, Equatable {
    public let status: WidgetWeaverStepsAuthorisationStatus
    public let debug: String?

    public init(status: WidgetWeaverStepsAuthorisationStatus, debug: String?) {
        self.status = status
        self.debug = debug
    }
}

public struct WidgetWeaverStepsUpdateResult: Sendable {
    public let snapshot: WidgetWeaverStepsSnapshot?
    public let errorDescription: String?

    public init(snapshot: WidgetWeaverStepsSnapshot?, errorDescription: String? = nil) {
        self.snapshot = snapshot
        self.errorDescription = errorDescription
    }
}

#if canImport(HealthKit)
public struct WidgetWeaverStepsProbeFailure: Error, Sendable, Equatable {
    public let status: WidgetWeaverStepsAuthorisationStatus
    public let debugMessage: String

    public init(status: WidgetWeaverStepsAuthorisationStatus, debugMessage: String) {
        self.status = status
        self.debugMessage = debugMessage
    }
}
#endif

public final class WidgetWeaverStepsEngine: @unchecked Sendable {
    public static let shared = WidgetWeaverStepsEngine()

    private let store = WidgetWeaverStepsStore.shared
    #if canImport(HealthKit)
    private let healthStore = HKHealthStore()
    #endif

    private init() {}

    public func requestReadAuthorisation() async -> Bool {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return false }

        return await withCheckedContinuation { continuation in
            healthStore.requestAuthorization(toShare: [], read: [stepType]) { success, _ in
                continuation.resume(returning: success)
            }
        }
        #else
        return false
        #endif
    }

    public func readAuthorisationProbe() async -> WidgetWeaverStepsReadProbe {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else {
            return WidgetWeaverStepsReadProbe(status: .unavailable, debug: "Health data unavailable on this device.")
        }
        guard HKQuantityType.quantityType(forIdentifier: .stepCount) != nil else {
            return WidgetWeaverStepsReadProbe(status: .unavailable, debug: "StepCount quantity type unavailable.")
        }

        let now = Date()
        switch await probeTodayStepCount(now: now) {
        case .success:
            return WidgetWeaverStepsReadProbe(status: .authorised, debug: nil)
        case .failure(let failure):
            return WidgetWeaverStepsReadProbe(status: failure.status, debug: failure.debugMessage)
        }
        #else
        return WidgetWeaverStepsReadProbe(status: .unavailable, debug: "HealthKit not available.")
        #endif
    }

    public func updateIfNeeded(force: Bool) async -> WidgetWeaverStepsUpdateResult {
        let now = Date()
        let refreshWindow = store.recommendedRefreshIntervalSeconds()

        if !force, let existing = store.snapshotForToday(now: now) {
            let age = now.timeIntervalSince(existing.fetchedAt)
            if age >= 0, age < refreshWindow {
                return WidgetWeaverStepsUpdateResult(snapshot: existing)
            }
        }

        #if canImport(HealthKit)
        switch await probeTodayStepCount(now: now) {
        case .success(let steps):
            let calendar = Calendar.autoupdatingCurrent
            let snap = WidgetWeaverStepsSnapshot(
                stepsToday: steps,
                startOfDay: calendar.startOfDay(for: now),
                fetchedAt: now
            )
            store.saveSnapshot(snap)
            return WidgetWeaverStepsUpdateResult(snapshot: snap)

        case .failure(let failure):
            let headline: String = {
                switch failure.status {
                case .authorised: return "Steps authorised."
                case .notDetermined: return "Steps access not enabled yet."
                case .denied: return "Steps access denied."
                case .unavailable: return "Health data unavailable."
                }
            }()
            return WidgetWeaverStepsUpdateResult(
                snapshot: store.snapshotForToday(now: now),
                errorDescription: "\(headline)\n\(failure.debugMessage)"
            )
        }
        #else
        return WidgetWeaverStepsUpdateResult(
            snapshot: store.snapshotForToday(now: now),
            errorDescription: "HealthKit not available."
        )
        #endif
    }

    #if canImport(HealthKit)
    private func probeTodayStepCount(now: Date) async -> Result<Int, WidgetWeaverStepsProbeFailure> {
        do {
            let steps = try await queryTodayStepCount(now: now)
            return .success(steps)
        } catch {
            let ns = error as NSError

            let domain = ns.domain
            let code = ns.code
            let descLower = ns.localizedDescription.lowercased()
            let reasonLower = (ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?.lowercased() ?? ""

            // HealthKit “No data available…” is not a permission denial.
            // It simply means there are no step samples matching the predicate (often 0 steps today).
            // This has historically been domain "com.apple.healthkit" code 11, but the guard is intentionally forgiving.
            if code == 11, domain == "com.apple.healthkit" {
                return .success(0)
            }
            if descLower.contains("no data available") || reasonLower.contains("no data available") {
                return .success(0)
            }

            var debug = "\(domain) (\(code)): \(ns.localizedDescription)"
            if let reason = ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String, !reason.isEmpty {
                debug += " — \(reason)"
            }

            if domain == "com.apple.healthkit" {
                if code == HKError.errorAuthorizationNotDetermined.rawValue {
                    return .failure(WidgetWeaverStepsProbeFailure(status: .notDetermined, debugMessage: debug))
                }
                if code == HKError.errorAuthorizationDenied.rawValue {
                    return .failure(WidgetWeaverStepsProbeFailure(status: .denied, debugMessage: debug))
                }
                if code == HKError.errorHealthDataUnavailable.rawValue {
                    return .failure(WidgetWeaverStepsProbeFailure(status: .unavailable, debugMessage: debug))
                }

                // Unknown HealthKit-domain errors should not be mislabeled as "Denied".
                return .failure(WidgetWeaverStepsProbeFailure(status: .unavailable, debugMessage: debug))
            }

            // Non-HealthKit domain errors are treated as unavailable (not denied).
            return .failure(WidgetWeaverStepsProbeFailure(status: .unavailable, debugMessage: debug))
        }
    }

    private func queryTodayStepCount(now: Date) async throws -> Int {
        guard let stepType = HKQuantityType.quantityType(forIdentifier: .stepCount) else { return 0 }

        let calendar = Calendar.autoupdatingCurrent
        let start = calendar.startOfDay(for: now)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: now, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(
                quantityType: stepType,
                quantitySamplePredicate: predicate,
                options: .cumulativeSum
            ) { _, result, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let sum = result?.sumQuantity()?.doubleValue(for: .count()) ?? 0
                continuation.resume(returning: Int(sum.rounded(.down)))
            }

            healthStore.execute(query)
        }
    }
    #endif
}
