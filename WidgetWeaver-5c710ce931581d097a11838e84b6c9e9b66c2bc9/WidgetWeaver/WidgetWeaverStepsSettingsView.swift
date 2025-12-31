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
    @State private var access: WidgetWeaverStepsAccess = .unknown
    @State private var lastError: String?
    @State private var statusMessage: String?

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

                Text("Steps are read from Health. Refreshing here keeps widgets snappy.")
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
        access = store.loadLastAccess()
        lastError = store.loadLastError()

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

    private func refresh(force: Bool) async {
        if isRefreshing { return }
        isRefreshing = true
        defer { isRefreshing = false }

        let result = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: force)
        snapshot = result.snapshot
        access = result.access
        lastError = WidgetWeaverStepsStore.shared.loadLastError()
        statusMessage = nil

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
