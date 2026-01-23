//
//  WidgetWeaverStepsSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import SwiftUI

// MARK: - Steps settings

struct WidgetWeaverStepsSettingsView: View {
    let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    @AppStorage(WidgetWeaverStepsStore.Keys.weekdayGoalSteps, store: AppGroup.userDefaults)
    private var weekdayGoalSteps: Int = 10_000

    @AppStorage(WidgetWeaverStepsStore.Keys.weekendGoalSteps, store: AppGroup.userDefaults)
    private var weekendGoalSteps: Int = 10_000

    @AppStorage(WidgetWeaverStepsStore.Keys.streakRule, store: AppGroup.userDefaults)
    private var streakRuleRaw: String = WidgetWeaverStepsStreakRule.completeDaysOnly.rawValue

    @State private var isRefreshing: Bool = false
    @State private var snapshot: WidgetWeaverStepsSnapshot?
    @State private var history: WidgetWeaverStepsHistorySnapshot?
    @State private var access: WidgetWeaverStepsAccess = .unknown
    @State private var lastError: String?
    @State private var statusMessage: String?

    @State private var activitySnapshot: WidgetWeaverActivitySnapshot?
    @State private var activityAccess: WidgetWeaverActivityAccess = .unknown
    @State private var activityLastError: String?
    @State private var activityStatusMessage: String?

    private var schedule: WidgetWeaverStepsGoalSchedule {
        WidgetWeaverStepsGoalSchedule(
            weekdayGoalSteps: WidgetWeaverStepsGoalSchedule.clampGoal(weekdayGoalSteps),
            weekendGoalSteps: WidgetWeaverStepsGoalSchedule.clampGoal(weekendGoalSteps)
        )
    }

    private var streakRule: WidgetWeaverStepsStreakRule {
        WidgetWeaverStepsStreakRule(rawValue: streakRuleRaw) ?? .completeDaysOnly
    }

    private var todayGoal: Int { schedule.goalSteps(for: Date()) }
    private var todaySteps: Int { snapshot?.steps ?? 0 }
    private var todayFraction: Double {
        guard todayGoal > 0 else { return 0 }
        return min(1.0, max(0.0, Double(todaySteps) / Double(todayGoal)))
    }
    private var todayPercent: Int { Int((todayFraction * 100.0).rounded()) }

    private var stepsAnalytics: WidgetWeaverStepsAnalytics? {
        guard let history else { return nil }
        return WidgetWeaverStepsAnalytics(
            history: history,
            schedule: schedule,
            streakRule: streakRule
        )
    }


    var body: some View {
        List {
            Section {
                StepsTodayCard(
                    steps: todaySteps,
                    goal: todayGoal,
                    fraction: todayFraction,
                    percent: todayPercent,
                    access: access,
                    fetchedAt: snapshot?.fetchedAt
                )
            }


            Section("Insights") {
                if let analytics = stepsAnalytics {
                    StepsInsightsBarCompact(analytics: analytics)

                    if let best = analytics.bestDay {
                        Text("Best day: \(wwDateMedium(best.dayStart)) • \(wwFormatSteps(best.steps)) steps")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if let fetchedAt = history?.fetchedAt {
                        Text("History updated \(wwDateMedium(fetchedAt)) at \(wwTimeShort(fetchedAt))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("No history snapshot yet. Refresh Steps to build streak + average metrics.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("Open History for a full breakdown.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("Activity (steps + more)") {
                ActivityTodayCard(
                    snapshot: activitySnapshot,
                    access: activityAccess
                )

                if activityAccess == .authorised || activityAccess == .partial {
                    ActivityMetricsBar(snapshot: activitySnapshot)
                }

                if let activityLastError, !activityLastError.isEmpty {
                    Text(activityLastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if activityAccess == .notDetermined || activityAccess == .denied || activityAccess == .unknown {
                    Button {
                        Task { await requestActivityAccessAndRefresh() }
                    } label: {
                        Label("Request Activity Access", systemImage: "hand.raised.fill")
                    }
                    .disabled(isRefreshing)

                    Text("This requests read access for Steps, Flights Climbed, Walking/Running Distance, and Active Energy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                NavigationLink {
                    WidgetWeaverActivitySettingsView()
                } label: {
                    HStack {
                        Image(systemName: "info.circle")
                        Text("Activity details & __activity_* keys")
                    }
                }

                if let activityStatusMessage, !activityStatusMessage.isEmpty {
                    Text(activityStatusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Activity metrics are cached for widget rendering and can be used inside any design via built-in __activity_* keys.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Goal schedule") {
                Stepper(value: $weekdayGoalSteps, in: 0...200_000, step: 250) {
                    HStack {
                        Text("Weekdays")
                        Spacer()
                        Text(weekdayGoalSteps == 0 ? "Off" : wwFormatSteps(weekdayGoalSteps))
                            .foregroundStyle(.secondary)
                    }
                }

                Stepper(value: $weekendGoalSteps, in: 0...200_000, step: 250) {
                    HStack {
                        Text("Weekends")
                        Spacer()
                        Text(weekendGoalSteps == 0 ? "Off" : wwFormatSteps(weekendGoalSteps))
                            .foregroundStyle(.secondary)
                    }
                }

                Text("Set a goal to Off (0) for rest days. With the Fair rule, rest days are skipped (don’t count and don’t break the streak).")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: weekdayGoalSteps) { _, newValue in
                let g = WidgetWeaverStepsGoalSchedule.clampGoal(newValue)
                if g != newValue { weekdayGoalSteps = g }
                persistSchedule()
            }
            .onChange(of: weekendGoalSteps) { _, newValue in
                let g = WidgetWeaverStepsGoalSchedule.clampGoal(newValue)
                if g != newValue { weekendGoalSteps = g }
                persistSchedule()
            }

            Section("Streak rules") {
                Picker("Rule", selection: $streakRuleRaw) {
                    ForEach(WidgetWeaverStepsStreakRule.allCases) { r in
                        Text(r.displayName).tag(r.rawValue)
                    }
                }
                .pickerStyle(.segmented)

                Text(streakRule.helpText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .onChange(of: streakRuleRaw) { _, _ in
                WidgetWeaverStepsStore.shared.saveStreakRule(streakRule)
                WidgetSpecStore.shared.reloadWidgets()
            }

            Section("Steps access") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(accessLabel(access))
                        .foregroundStyle(.secondary)
                }

                if let lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if access == .notDetermined || access == .denied || access == .unknown {
                    Button {
                        Task { await requestAccessAndRefresh() }
                    } label: {
                        Label("Request Steps Access", systemImage: "hand.raised.fill")
                    }
                    .disabled(isRefreshing)
                }

                Button {
                    Task { await refresh(force: true) }
                } label: {
                    HStack {
                        Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        Text(isRefreshing ? "Refreshing…" : "Refresh now")
                    }
                }
                .disabled(isRefreshing)

                if access == .denied {
                    Text("If access was denied, enable it in the Health app: Sharing → Apps → WidgetWeaver, then allow Steps.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Steps and Activity are read from Health. Refreshing here keeps widgets snappy.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("History") {
                NavigationLink {
                    WidgetWeaverStepsHistoryView(
                        schedule: schedule,
                        streakRule: streakRule
                    )
                } label: {
                    HStack {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                        Text("Timeline, calendar & heatmap")
                    }
                }
            }

            Section("Template variables") {
                Text("Use these built-in keys in any widget text:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text(verbatim: "__steps_today")
                    Text(verbatim: "__steps_goal_today")
                    Text(verbatim: "__steps_today_percent")
                    Text(verbatim: "__steps_streak")
                    Text(verbatim: "__steps_avg_7")
                    Text(verbatim: "__steps_avg_30")
                    Text(verbatim: "__steps_best_day")
                    Text(verbatim: "__steps_best_day_date")
                    Text(verbatim: "__steps_updated_iso")
                    Text(verbatim: "__steps_access")
                }
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

                Text("History-derived keys (streak, averages, best day) require a cached history snapshot.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        }
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onClose() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Data

    private func load() async {
        let store = WidgetWeaverStepsStore.shared
        snapshot = store.snapshotForToday()
        history = store.loadHistory()
        access = store.loadLastAccess()
        lastError = store.loadLastError()

        let activityStore = WidgetWeaverActivityStore.shared
        activitySnapshot = activityStore.snapshotForToday()
        activityAccess = activityStore.loadLastAccess()
        activityLastError = activityStore.loadLastError()

        let s = store.loadGoalSchedule()
        weekdayGoalSteps = s.weekdayGoalSteps
        weekendGoalSteps = s.weekendGoalSteps
        streakRuleRaw = store.loadStreakRule().rawValue

        await refresh(force: false)
    }

    private func requestAccessAndRefresh() async {
        statusMessage = nil
        let ok = await WidgetWeaverStepsEngine.shared.requestReadAuthorisation()
        await refresh(force: true)
        statusMessage = ok ? "Access request completed." : "Access request failed."
    }

    private func requestActivityAccessAndRefresh() async {
        activityStatusMessage = nil
        let ok = await WidgetWeaverActivityEngine.shared.requestReadAuthorisation()
        await refresh(force: true)
        activityStatusMessage = ok ? "Access request completed." : "Access request failed."
    }

    private func refresh(force: Bool) async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let stepsResult = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: force)
        snapshot = stepsResult.snapshot
        access = stepsResult.access

        let updatedHistory = await WidgetWeaverStepsEngine.shared.updateHistoryFromBeginningIfNeeded(force: force)
        history = updatedHistory ?? WidgetWeaverStepsStore.shared.loadHistory()

        lastError = WidgetWeaverStepsStore.shared.loadLastError()

        let activityResult = await WidgetWeaverActivityEngine.shared.updateIfNeeded(force: force)
        activitySnapshot = activityResult.snapshot
        activityAccess = activityResult.access
        activityLastError = WidgetWeaverActivityStore.shared.loadLastError()

        statusMessage = nil
        activityStatusMessage = nil

        WidgetSpecStore.shared.reloadWidgets()
    }

    private func persistSchedule() {
        WidgetWeaverStepsStore.shared.saveGoalSchedule(
            WidgetWeaverStepsGoalSchedule(weekdayGoalSteps: weekdayGoalSteps, weekendGoalSteps: weekendGoalSteps),
            writeLegacyKey: true
        )
        WidgetSpecStore.shared.reloadWidgets()
    }

    private func accessLabel(_ access: WidgetWeaverStepsAccess) -> String {
        switch access {
        case .unknown: return "Unknown"
        case .notAvailable: return "Unavailable"
        case .notDetermined: return "Not enabled"
        case .authorised: return "Enabled"
        case .denied: return "Denied"
        }
    }
}


// MARK: - Activity metrics (in-app)

private struct ActivityMetricsBar: View {
    let snapshot: WidgetWeaverActivitySnapshot?

    var body: some View {
        let flights = snapshot?.flightsClimbed.map { "\($0)" } ?? "—"
        let distance = snapshot?.distanceWalkingRunningMeters.map(wwFormatDistanceKM) ?? "—"
        let energy = snapshot?.activeEnergyBurnedKilocalories.map(wwFormatKcal) ?? "—"

        return HStack(spacing: 10) {
            ActivityMetricPill(systemImage: "arrow.up", title: "Flights", value: flights)
            ActivityMetricPill(systemImage: "map", title: "Distance", value: distance)
            ActivityMetricPill(systemImage: "flame.fill", title: "Energy", value: energy)
        }
    }
}

private struct ActivityMetricPill: View {
    let systemImage: String
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}


// MARK: - Activity settings

struct WidgetWeaverActivitySettingsView: View {
    let onClose: (() -> Void)?

    init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }

    @State private var isRefreshing: Bool = false
    @State private var snapshot: WidgetWeaverActivitySnapshot?
    @State private var access: WidgetWeaverActivityAccess = .unknown
    @State private var lastError: String?
    @State private var statusMessage: String?

    var body: some View {
        List {
            Section {
                ActivityTodayCard(
                    snapshot: snapshot,
                    access: access
                )
            }

            Section("Activity access") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(accessLabel(access))
                        .foregroundStyle(.secondary)
                }

                if let lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if access == .notDetermined || access == .denied || access == .unknown {
                    Button {
                        Task { await requestAccessAndRefresh() }
                    } label: {
                        Label("Request Activity Access", systemImage: "hand.raised.fill")
                    }
                    .disabled(isRefreshing)

                    Text("This requests read access for Steps, Flights Climbed, Walking/Running Distance, and Active Energy.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Button {
                    Task { await refresh(force: true) }
                } label: {
                    HStack {
                        Image(systemName: isRefreshing ? "arrow.triangle.2.circlepath" : "arrow.clockwise")
                        Text(isRefreshing ? "Refreshing…" : "Refresh now")
                    }
                }
                .disabled(isRefreshing)

                if access == .denied {
                    Text("If access was denied, enable it in the Health app: Sharing → Apps → WidgetWeaver, then allow the activity types you want.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Text("Activity data is read on-device from HealthKit and cached so widgets render quickly.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Section("Template variables") {
                Text("Use these built-in keys in any widget text:")
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("__activity_steps_today")
                    Text("__activity_flights_today")
                    Text("__activity_distance_km")
                    Text("__activity_active_energy_kcal")
                    Text("__activity_updated_iso")
                    Text("__activity_access")
                }
                .font(.system(.footnote, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)

                Text("Keys appear once Health access is enabled and a snapshot is cached.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Activity")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { onClose() }
                }
            }
        }
        .task { await load() }
    }

    // MARK: - Data

    private func load() async {
        let store = WidgetWeaverActivityStore.shared
        snapshot = store.snapshotForToday()
        access = store.loadLastAccess()
        lastError = store.loadLastError()

        await refresh(force: false)
    }

    private func requestAccessAndRefresh() async {
        statusMessage = nil
        let ok = await WidgetWeaverActivityEngine.shared.requestReadAuthorisation()
        await refresh(force: true)
        statusMessage = ok ? "Access request completed." : "Access request failed."
    }

    private func refresh(force: Bool) async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await WidgetWeaverActivityEngine.shared.updateIfNeeded(force: force)
        snapshot = result.snapshot
        access = result.access
        lastError = WidgetWeaverActivityStore.shared.loadLastError()
        statusMessage = nil

        WidgetSpecStore.shared.reloadWidgets()
    }

    private func accessLabel(_ access: WidgetWeaverActivityAccess) -> String {
        switch access {
        case .unknown: return "Unknown"
        case .notAvailable: return "Unavailable"
        case .notDetermined: return "Not enabled"
        case .authorised: return "Enabled"
        case .denied: return "Denied"
        case .partial: return "Partial"
        }
    }
}
