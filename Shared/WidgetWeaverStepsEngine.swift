//
//  WidgetWeaverStepsEngine.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//
//  HealthKit-backed engine for fetching Steps snapshots + history.
//

import Foundation
#if canImport(HealthKit)
@preconcurrency import HealthKit
#endif

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

            if Self.isAuthorisationNotDeterminedError(ns) {
                store.saveLastAccess(.notDetermined)
                store.saveLastError("Steps access isn’t enabled yet. Tap “Request Steps Access”.")
                return Result(snapshot: store.snapshotForToday(), access: .notDetermined, errorDescription: store.loadLastError())
            }

            if Self.isAuthorisationDeniedError(ns) {
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

            if Self.isAuthorisationNotDeterminedError(ns) {
                store.saveLastAccess(.notDetermined)
                store.saveLastError("Steps access isn’t enabled yet. Tap “Request Steps Access”.")
                return store.loadHistory()
            }

            if Self.isAuthorisationDeniedError(ns) {
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

    nonisolated private static func isHealthKitDomain(_ domain: String) -> Bool {
        if domain == HKErrorDomain { return true }
        if domain == "com.apple.healthkit" { return true }
        return false
    }

    nonisolated private static func isNoDataAvailableError(_ ns: NSError) -> Bool {
        if Self.isHealthKitDomain(ns.domain) && ns.code == 11 { return true }
        let d = ns.localizedDescription.lowercased()
        if d.contains("no data available") { return true }
        let r = (ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?.lowercased() ?? ""
        if r.contains("no data available") { return true }
        return false
    }

    nonisolated private static func isAuthorisationNotDeterminedError(_ ns: NSError) -> Bool {
        if Self.isHealthKitDomain(ns.domain) && ns.code == 5 { return true }
        let d = ns.localizedDescription.lowercased()
        if d.contains("authorization not determined") { return true }
        if d.contains("authorisation not determined") { return true }
        return false
    }

    nonisolated private static func isAuthorisationDeniedError(_ ns: NSError) -> Bool {
        if Self.isHealthKitDomain(ns.domain) && ns.code == 4 { return true }
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
                    if Self.isNoDataAvailableError(error) {
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
                    if Self.isNoDataAvailableError(error) {
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

    private func fetchDailySteps(
        healthStore: HKHealthStore,
        stepsType: HKQuantityType,
        startDay: Date,
        endDay: Date
    ) async throws -> [WidgetWeaverStepsDayPoint] {
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
                    if Self.isNoDataAvailableError(error) {
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


// MARK: - Activity Engine (HealthKit-backed multi-metric snapshot)

public actor WidgetWeaverActivityEngine {
    public static let shared = WidgetWeaverActivityEngine()

    public struct Result: Sendable {
        public var snapshot: WidgetWeaverActivitySnapshot?
        public var access: WidgetWeaverActivityAccess
        public var errorDescription: String?

        public init(snapshot: WidgetWeaverActivitySnapshot?, access: WidgetWeaverActivityAccess, errorDescription: String?) {
            self.snapshot = snapshot
            self.access = access
            self.errorDescription = errorDescription
        }
    }

    public var minimumUpdateInterval: TimeInterval = 60 * 15

    private var inFlightSnapshot: Task<Result, Never>?

    public func requestReadAuthorisation() async -> Bool {
        let store = WidgetWeaverActivityStore.shared

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

        let readTypes = Self.readTypesAvailable()
        guard !readTypes.isEmpty else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Activity data types are not available.")
            return false
        }

        let healthStore = HKHealthStore()
        return await withCheckedContinuation { cont in
            healthStore.requestAuthorization(toShare: [], read: readTypes) { success, error in
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

    private func updateSnapshot(force: Bool) async -> Result {
        let store = WidgetWeaverActivityStore.shared

        #if !canImport(HealthKit)
        store.saveLastAccess(.notAvailable)
        store.saveLastError("HealthKit unavailable")
        return Result(snapshot: store.snapshotForToday(), access: .notAvailable, errorDescription: store.loadLastError())
        #else

        #if targetEnvironment(simulator)
        let snap = WidgetWeaverActivitySnapshot.sample()
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

        let readTypes = Self.readTypesAvailable()
        guard !readTypes.isEmpty else {
            store.saveLastAccess(.notAvailable)
            store.saveLastError("Activity data types are not available.")
            return Result(snapshot: store.snapshotForToday(), access: .notAvailable, errorDescription: store.loadLastError())
        }

        let req = await requestStatusForRead(healthStore: healthStore, readTypes: readTypes)
        if req == .shouldRequest {
            store.saveLastAccess(.notDetermined)
            store.saveLastError("Activity access isn’t enabled yet. Tap “Request Activity Access”.")
            return Result(snapshot: store.snapshotForToday(), access: .notDetermined, errorDescription: store.loadLastError())
        }

        let cal = Calendar.autoupdatingCurrent
        let now = Date()
        let start = cal.startOfDay(for: now)

        var steps: Int?
        var flights: Int?
        var distanceM: Double?
        var energyKcal: Double?

        var missing: [String] = []
        var hadDenied: Bool = false
        var hadNotDetermined: Bool = false
        var otherError: NSError?

        func handleError(_ ns: NSError, label: String) {
            if Self.isAuthorisationNotDeterminedError(ns) {
                hadNotDetermined = true
                missing.append(label)
                return
            }
            if Self.isAuthorisationDeniedError(ns) {
                hadDenied = true
                missing.append(label)
                return
            }
            otherError = ns
        }

        // Steps
        if let t = HKQuantityType.quantityType(forIdentifier: .stepCount) {
            do {
                let v = try await fetchCumulativeSumForToday(healthStore: healthStore, quantityType: t, unit: .count())
                steps = Int(v.rounded())
            } catch {
                let ns = error as NSError
                if Self.isNoDataAvailableError(ns) {
                    steps = 0
                } else {
                    handleError(ns, label: "Steps")
                }
            }
        }

        // Flights
        if let t = HKQuantityType.quantityType(forIdentifier: .flightsClimbed) {
            do {
                let v = try await fetchCumulativeSumForToday(healthStore: healthStore, quantityType: t, unit: .count())
                flights = Int(v.rounded())
            } catch {
                let ns = error as NSError
                if Self.isNoDataAvailableError(ns) {
                    flights = 0
                } else {
                    handleError(ns, label: "Flights")
                }
            }
        }

        // Distance
        if let t = HKQuantityType.quantityType(forIdentifier: .distanceWalkingRunning) {
            do {
                let v = try await fetchCumulativeSumForToday(healthStore: healthStore, quantityType: t, unit: .meter())
                distanceM = v
            } catch {
                let ns = error as NSError
                if Self.isNoDataAvailableError(ns) {
                    distanceM = 0
                } else {
                    handleError(ns, label: "Distance")
                }
            }
        }

        // Active energy
        if let t = HKQuantityType.quantityType(forIdentifier: .activeEnergyBurned) {
            do {
                let v = try await fetchCumulativeSumForToday(healthStore: healthStore, quantityType: t, unit: .kilocalorie())
                energyKcal = v
            } catch {
                let ns = error as NSError
                if Self.isNoDataAvailableError(ns) {
                    energyKcal = 0
                } else {
                    handleError(ns, label: "Active Energy")
                }
            }
        }

        // Decide access state.
        let anyValuePresent =
            steps != nil || flights != nil || distanceM != nil || energyKcal != nil

        if let otherError {
            store.saveLastAccess(.unknown)
            store.saveLastError("\(otherError.domain) (\(otherError.code)): \(otherError.localizedDescription)")
            return Result(snapshot: store.snapshotForToday(), access: store.loadLastAccess(), errorDescription: store.loadLastError())
        }

        let access: WidgetWeaverActivityAccess
        if !anyValuePresent {
            if hadNotDetermined {
                access = .notDetermined
            } else if hadDenied {
                access = .denied
            } else {
                access = .unknown
            }
        } else if !missing.isEmpty {
            access = .partial
        } else {
            access = .authorised
        }

        let snap = WidgetWeaverActivitySnapshot(
            fetchedAt: now,
            startOfDay: start,
            steps: steps,
            flightsClimbed: flights,
            distanceWalkingRunningMeters: distanceM,
            activeEnergyBurnedKilocalories: energyKcal
        )

        store.saveSnapshot(snap)
        store.saveLastAccess(access)

        if access == .notDetermined {
            store.saveLastError("Activity access isn’t enabled yet. Tap “Request Activity Access”.")
        } else if access == .denied {
            store.saveLastError("Activity access is denied. Enable it in the Health app (Sharing → Apps → WidgetWeaver).")
        } else if access == .partial {
            let list = missing.sorted().joined(separator: ", ")
            store.saveLastError("Some activity types aren’t enabled: \(list). Enable them in the Health app (Sharing → Apps → WidgetWeaver).")
        } else {
            store.saveLastError(nil)
        }

        return Result(snapshot: snap, access: access, errorDescription: store.loadLastError())

        #endif
        #endif
    }

    // MARK: - HealthKit helpers

    #if canImport(HealthKit)
    private func requestStatusForRead(healthStore: HKHealthStore, readTypes: Set<HKObjectType>) async -> HKAuthorizationRequestStatus {
        await withCheckedContinuation { cont in
            healthStore.getRequestStatusForAuthorization(toShare: [], read: readTypes) { status, _ in
                cont.resume(returning: status)
            }
        }
    }

    private static func readTypesAvailable() -> Set<HKObjectType> {
        var out: Set<HKObjectType> = []

        if let t = HKObjectType.quantityType(forIdentifier: .stepCount) { out.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .flightsClimbed) { out.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .distanceWalkingRunning) { out.insert(t) }
        if let t = HKObjectType.quantityType(forIdentifier: .activeEnergyBurned) { out.insert(t) }

        return out
    }

    nonisolated private static func isHealthKitDomain(_ domain: String) -> Bool {
        if domain == HKErrorDomain { return true }
        if domain == "com.apple.healthkit" { return true }
        return false
    }

    nonisolated private static func isNoDataAvailableError(_ ns: NSError) -> Bool {
        if Self.isHealthKitDomain(ns.domain) && ns.code == 11 { return true }
        let d = ns.localizedDescription.lowercased()
        if d.contains("no data available") { return true }
        let r = (ns.userInfo[NSLocalizedFailureReasonErrorKey] as? String)?.lowercased() ?? ""
        if r.contains("no data available") { return true }
        return false
    }

    nonisolated private static func isAuthorisationNotDeterminedError(_ ns: NSError) -> Bool {
        if Self.isHealthKitDomain(ns.domain) && ns.code == 5 { return true }
        let d = ns.localizedDescription.lowercased()
        if d.contains("authorization not determined") { return true }
        if d.contains("authorisation not determined") { return true }
        return false
    }

    nonisolated private static func isAuthorisationDeniedError(_ ns: NSError) -> Bool {
        if Self.isHealthKitDomain(ns.domain) && ns.code == 4 { return true }
        let d = ns.localizedDescription.lowercased()
        if d.contains("authorization denied") { return true }
        if d.contains("authorisation denied") { return true }
        if d.contains("not authorized") { return true }
        if d.contains("not authorised") { return true }
        return false
    }

    private func fetchCumulativeSumForToday(healthStore: HKHealthStore, quantityType: HKQuantityType, unit: HKUnit) async throws -> Double {
        let cal = Calendar.autoupdatingCurrent
        let now = Date()
        let start = cal.startOfDay(for: now)
        let end = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)

        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: .strictStartDate)

        return try await withCheckedThrowingContinuation { continuation in
            let query = HKStatisticsQuery(quantityType: quantityType, quantitySamplePredicate: predicate, options: .cumulativeSum) { _, stats, error in
                if let error = error as NSError? {
                    continuation.resume(throwing: error)
                    return
                }
                let sum = stats?.sumQuantity()?.doubleValue(for: unit) ?? 0
                continuation.resume(returning: sum)
            }
            healthStore.execute(query)
        }
    }
    #endif
}
