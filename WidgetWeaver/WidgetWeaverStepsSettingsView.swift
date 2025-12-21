//
//  WidgetWeaverStepsSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import SwiftUI
import WidgetKit
import UIKit

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

// MARK: - History view (timeline + month + year)

private struct WidgetWeaverStepsHistoryView: View {
    enum Mode: String, CaseIterable, Identifiable {
        case timeline
        case month
        case year
        var id: String { rawValue }
        var title: String {
            switch self {
            case .timeline: return "Timeline"
            case .month: return "Month"
            case .year: return "Year"
            }
        }
    }

    let schedule: WidgetWeaverStepsGoalSchedule
    let streakRule: WidgetWeaverStepsStreakRule

    @State private var isLoading: Bool = false
    @State private var history: WidgetWeaverStepsHistorySnapshot?
    @State private var error: String?

    @State private var mode: Mode = .timeline
    @State private var scrollTarget: Date? = nil
    @State private var monthCursor: Date = Date()
    @State private var yearCursor: Int = Calendar.autoupdatingCurrent.component(.year, from: Date())

    private var cal: Calendar { .autoupdatingCurrent }

    var body: some View {
        Group {
            if let history {
                content(history)
            } else if isLoading {
                ProgressView("Loading…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                empty
            }
        }
        .navigationTitle("History")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await loadHistory(force: true) }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .disabled(isLoading)
            }
        }
        .task { await loadHistory(force: false) }
    }

    @ViewBuilder
    private func content(_ history: WidgetWeaverStepsHistorySnapshot) -> some View {
        let analytics = WidgetWeaverStepsAnalytics(history: history, schedule: schedule, streakRule: streakRule)

        VStack(spacing: 10) {
            Picker("View", selection: $mode) {
                ForEach(Mode.allCases) { m in
                    Text(m.title).tag(m)
                }
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)

            if mode == .timeline {
                StepsInsightsBar(analytics: analytics)
                    .padding(.horizontal, 16)

                StepsTimelineView(
                    history: history,
                    schedule: schedule,
                    scrollTarget: $scrollTarget
                )
                .padding(.horizontal, 16)
            } else if mode == .month {
                StepsMonthCalendarView(
                    history: history,
                    schedule: schedule,
                    monthCursor: $monthCursor,
                    onSelectDay: { dayStart in
                        scrollTarget = dayStart
                        mode = .timeline
                    }
                )
                .padding(.horizontal, 16)
            } else {
                StepsYearHeatmapView(
                    history: history,
                    schedule: schedule,
                    year: $yearCursor,
                    onSelectDay: { dayStart in
                        scrollTarget = dayStart
                        mode = .timeline
                    }
                )
                .padding(.horizontal, 16)
            }
        }
        .padding(.vertical, 10)
        .onAppear { seedCursorsIfNeeded(history) }
    }

    private var empty: some View {
        VStack(spacing: 12) {
            Image(systemName: "figure.walk")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("No history yet")
                .font(.headline)

            Text(error ?? "Refresh Steps to build your history.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button("Load history") {
                Task { await loadHistory(force: true) }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func seedCursorsIfNeeded(_ history: WidgetWeaverStepsHistorySnapshot) {
        let latest = history.latestDay
        yearCursor = cal.component(.year, from: latest)
        monthCursor = cal.dateInterval(of: .month, for: latest)?.start ?? latest
    }

    private func loadHistory(force: Bool) async {
        if isLoading { return }
        isLoading = true
        defer { isLoading = false }

        _ = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: false)

        let updated = await WidgetWeaverStepsEngine.shared.updateHistoryFromBeginningIfNeeded(force: force)
        if let updated {
            history = updated
            error = nil
            seedCursorsIfNeeded(updated)
        } else {
            history = WidgetWeaverStepsStore.shared.loadHistory()
            error = WidgetWeaverStepsStore.shared.loadLastError()
        }
    }
}

// MARK: - Insights bar

private struct StepsInsightsBar: View {
    let analytics: WidgetWeaverStepsAnalytics

    var body: some View {
        HStack(spacing: 10) {
            InsightPill(title: "Streak", value: "\(analytics.currentStreakDays)d")
            InsightPill(title: "Avg 7", value: wwFormatSteps(Int(analytics.averageSteps(days: 7).rounded())))
            InsightPill(title: "Avg 30", value: wwFormatSteps(Int(analytics.averageSteps(days: 30).rounded())))
        }
    }
}

private struct InsightPill: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}

// MARK: - Timeline

private struct StepsTimelineView: View {
    let history: WidgetWeaverStepsHistorySnapshot
    let schedule: WidgetWeaverStepsGoalSchedule

    @Binding var scrollTarget: Date?

    @State private var showOnlyHits: Bool = false
    @State private var pinnedMessage: String?

    private var cal: Calendar { .autoupdatingCurrent }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Toggle("Show only goal-hit days", isOn: $showOnlyHits)
                .font(.subheadline)

            if let pinnedMessage {
                Text(pinnedMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 10) {
                        ForEach(filteredDays) { point in
                            StepsDayRow(
                                point: point,
                                goal: schedule.goalSteps(for: point.dayStart, calendar: cal),
                                onPin: { pin(point) }
                            )
                            .id(point.dayStart)
                        }
                    }
                    .padding(.vertical, 6)
                }
                .onChange(of: scrollTarget) { _, newValue in
                    guard let newValue else { return }
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) {
                        proxy.scrollTo(newValue, anchor: .top)
                    }
                }
            }
        }
    }

    private var filteredDays: [WidgetWeaverStepsDayPoint] {
        let days = history.days.sorted(by: { $0.dayStart > $1.dayStart })
        guard showOnlyHits else { return days }
        return days.filter { point in
            let goal = schedule.goalSteps(for: point.dayStart, calendar: cal)
            return goal > 0 && point.steps >= goal
        }
    }

    private func pin(_ point: WidgetWeaverStepsDayPoint) {
        let cal = Calendar.autoupdatingCurrent
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = cal.timeZone
        df.dateFormat = "yyyy-MM-dd"

        let name = "Steps • \(df.string(from: point.dayStart))"

        var spec = WidgetSpec.defaultSpec()
        spec.id = UUID()
        spec.updatedAt = Date()
        spec.name = name
        spec.primaryText = "\(wwFormatSteps(point.steps)) steps"

        let pretty = wwDateMedium(point.dayStart)
        let goalForDay = schedule.goalSteps(for: point.dayStart, calendar: cal)
        if goalForDay > 0 {
            spec.secondaryText = "\(pretty) • \(point.steps >= goalForDay ? "Goal hit" : "Missed goal")"
        } else {
            spec.secondaryText = "\(pretty) • Rest day"
        }

        spec.symbol = SymbolSpec(
            name: "figure.walk",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )

        WidgetSpecStore.shared.save(spec, makeDefault: false)
        WidgetSpecStore.shared.reloadWidgets()
        pinnedMessage = "Pinned as design: \(name)"
    }
}

private struct StepsDayRow: View {
    let point: WidgetWeaverStepsDayPoint
    let goal: Int
    let onPin: () -> Void

    private var fraction: Double {
        guard goal > 0 else { return 0 }
        return min(1.0, max(0.0, Double(point.steps) / Double(goal)))
    }

    private var percent: Int { Int((fraction * 100.0).rounded()) }

    var body: some View {
        HStack(spacing: 12) {
            StepsRing(fraction: fraction, lineWidth: 8)
                .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(wwDateMedium(point.dayStart))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Text(wwFormatSteps(point.steps))
                    .font(.headline)
                    .bold()
                    .monospacedDigit()
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                if goal > 0 {
                    Text("\(percent)%")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                    Text(point.steps >= goal ? "Hit" : "Miss")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Rest")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button { onPin() } label: {
                Label("Pin this day", systemImage: "pin")
            }
            Button {
                UIPasteboard.general.string = "\(point.steps)"
            } label: {
                Label("Copy steps", systemImage: "doc.on.doc")
            }
        }
        .padding(.vertical, 6)
    }
}

// MARK: - Month calendar

private struct StepsMonthCalendarView: View {
    let history: WidgetWeaverStepsHistorySnapshot
    let schedule: WidgetWeaverStepsGoalSchedule

    @Binding var monthCursor: Date
    var onSelectDay: (Date) -> Void

    private var cal: Calendar { .autoupdatingCurrent }

    var body: some View {
        let start = cal.dateInterval(of: .month, for: monthCursor)?.start ?? monthCursor
        let gridDays = daysInMonthGrid(monthStart: start)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { monthCursor = cal.date(byAdding: .month, value: -1, to: start) ?? start } label: {
                    Image(systemName: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                Text(wwMonthTitle(start))
                    .font(.headline)

                Spacer()

                Button { monthCursor = cal.date(byAdding: .month, value: 1, to: start) ?? start } label: {
                    Image(systemName: "chevron.right")
                }
                .buttonStyle(.plain)
            }

            weekdayHeader

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 7), spacing: 10) {
                ForEach(gridDays.indices, id: \.self) { idx in
                    if let dayStart = gridDays[idx] {
                        dayCell(dayStart: dayStart)
                    } else {
                        Color.clear.frame(height: 38)
                    }
                }
            }
        }
    }

    private var weekdayHeader: some View {
        let symbols = cal.veryShortStandaloneWeekdaySymbols
        return HStack(spacing: 0) {
            ForEach(symbols.indices, id: \.self) { idx in
                Text(symbols[idx])
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    @ViewBuilder
    private func dayCell(dayStart: Date) -> some View {
        let steps = stepsForDay(dayStart)
        let goal = schedule.goalSteps(for: dayStart, calendar: cal)
        let hit = (goal > 0) ? (steps >= goal) : false
        let isToday = cal.isDateInToday(dayStart)

        Button { onSelectDay(dayStart) } label: {
            VStack(spacing: 4) {
                Text("\(cal.component(.day, from: dayStart))")
                    .font(.system(.subheadline, design: .rounded).weight(isToday ? .bold : .regular))
                    .frame(maxWidth: .infinity)

                Circle()
                    .fill(hit ? Color.accentColor : Color.secondary.opacity(goal > 0 ? 0.25 : 0.08))
                    .frame(width: 6, height: 6)
                    .opacity(goal > 0 ? 1.0 : 0.6)
            }
            .frame(height: 38)
        }
        .buttonStyle(.plain)
    }

    private func stepsForDay(_ dayStart: Date) -> Int {
        if let p = history.days.first(where: { cal.isDate($0.dayStart, inSameDayAs: dayStart) }) {
            return p.steps
        }
        return 0
    }

    private func daysInMonthGrid(monthStart: Date) -> [Date?] {
        guard let interval = cal.dateInterval(of: .month, for: monthStart) else { return [] }

        let firstDay = interval.start
        let range = cal.range(of: .day, in: .month, for: firstDay) ?? 1..<2
        let numDays = range.count

        let weekday = cal.component(.weekday, from: firstDay)
        let leading = (weekday - cal.firstWeekday + 7) % 7

        var out: [Date?] = Array(repeating: nil, count: leading)
        out.reserveCapacity(leading + numDays)

        for day in 1...numDays {
            if let d = cal.date(byAdding: .day, value: day - 1, to: firstDay) {
                out.append(cal.startOfDay(for: d))
            }
        }

        while out.count % 7 != 0 { out.append(nil) }
        return out
    }
}

// MARK: - Year heatmap

private struct StepsYearHeatmapView: View {
    let history: WidgetWeaverStepsHistorySnapshot
    let schedule: WidgetWeaverStepsGoalSchedule

    @Binding var year: Int
    var onSelectDay: (Date) -> Void

    private var cal: Calendar { .autoupdatingCurrent }

    var body: some View {
        let years = availableYears()
        let boundYear = years.contains(year) ? year : (years.last ?? year)
        let interval = yearInterval(boundYear)

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Year")
                    .font(.headline)
                Picker("Year", selection: $year) {
                    ForEach(years, id: \.self) { y in
                        Text("\(y)").tag(y)
                    }
                }
                .pickerStyle(.menu)
                Spacer()
            }

            StepsYearStats(history: history, schedule: schedule, year: boundYear)
                .padding(.vertical, 4)

            heatmap(interval: interval)
            legend
        }
    }

    private func heatmap(interval: DateInterval) -> some View {
        let start = interval.start
        let end = interval.end
        let startWeek = startOfWeek(start)
        let endWeek = startOfWeek(end)
        let weeks = weeksBetween(startWeek, endWeek)

        let byDay = stepsMap()
        let size: CGFloat = 11
        let spacing: CGFloat = 4

        return ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: spacing) {
                ForEach(0..<weeks, id: \.self) { w in
                    let weekStart = cal.date(byAdding: .day, value: w * 7, to: startWeek) ?? startWeek
                    VStack(spacing: spacing) {
                        ForEach(0..<7, id: \.self) { dayOffset in
                            let d = cal.date(byAdding: .day, value: dayOffset, to: weekStart) ?? weekStart
                            let dayStart = cal.startOfDay(for: d)
                            let inYear = (dayStart >= start && dayStart < end)
                            let steps = inYear ? (byDay[dayStart] ?? 0) : 0
                            let goal = inYear ? schedule.goalSteps(for: dayStart, calendar: cal) : 0
                            HeatmapCell(dayStart: dayStart, inYear: inYear, steps: steps, goal: goal, size: size) {
                                onSelectDay(dayStart)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 8)
        }
    }

    private var legend: some View {
        HStack(spacing: 8) {
            Text("Less")
                .font(.caption2)
                .foregroundStyle(.secondary)
            ForEach(0..<5, id: \.self) { level in
                RoundedRectangle(cornerRadius: 2)
                    .fill(Color.accentColor.opacity(legendOpacity(level)))
                    .frame(width: 12, height: 12)
            }
            Text("More")
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private func legendOpacity(_ level: Int) -> Double {
        switch level {
        case 0: return 0.10
        case 1: return 0.25
        case 2: return 0.40
        case 3: return 0.60
        default: return 0.85
        }
    }

    private func stepsMap() -> [Date: Int] {
        var dict: [Date: Int] = [:]
        dict.reserveCapacity(history.days.count)
        for p in history.days { dict[p.dayStart] = p.steps }
        return dict
    }

    private func availableYears() -> [Int] {
        let ys = Set(history.days.map { cal.component(.year, from: $0.dayStart) })
        return ys.sorted()
    }

    private func yearInterval(_ y: Int) -> DateInterval {
        let start = cal.date(from: DateComponents(year: y, month: 1, day: 1)) ?? Date()
        let end = cal.date(byAdding: .year, value: 1, to: start) ?? start.addingTimeInterval(365 * 86_400)
        return DateInterval(start: start, end: end)
    }

    private func startOfWeek(_ date: Date) -> Date {
        let d = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: d)
        let delta = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -delta, to: d) ?? d
    }

    private func weeksBetween(_ startWeek: Date, _ endWeek: Date) -> Int {
        let days = cal.dateComponents([.day], from: startWeek, to: endWeek).day ?? 0
        return max(1, (days / 7) + 1)
    }
}

private struct StepsYearStats: View {
    let history: WidgetWeaverStepsHistorySnapshot
    let schedule: WidgetWeaverStepsGoalSchedule
    let year: Int

    private var cal: Calendar { .autoupdatingCurrent }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let best = bestWeek() {
                HStack {
                    Text("Best week")
                    Spacer()
                    Text(wwFormatSteps(best.total))
                        .foregroundStyle(.secondary)
                }
                Text(best.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if let month = mostConsistentMonth() {
                HStack {
                    Text("Most consistent month")
                    Spacer()
                    Text("\(month.hit)/\(month.eligible) (\(Int((month.rate * 100).rounded()))%)")
                        .foregroundStyle(.secondary)
                }
                Text(month.label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background(Color.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private struct BestWeek {
        var total: Int
        var label: String
    }

    private func bestWeek() -> BestWeek? {
        let byDay: [Date: Int] = Dictionary(uniqueKeysWithValues: history.days.map { ($0.dayStart, $0.steps) })
        let start = cal.date(from: DateComponents(year: year, month: 1, day: 1)) ?? Date()
        let end = cal.date(byAdding: .year, value: 1, to: start) ?? start.addingTimeInterval(365 * 86_400)

        var cursor = startOfWeek(start)
        let endWeek = startOfWeek(end)

        var bestTotal = -1
        var bestLabel = ""

        while cursor <= endWeek {
            var total = 0
            for off in 0..<7 {
                let d = cal.date(byAdding: .day, value: off, to: cursor) ?? cursor
                let ds = cal.startOfDay(for: d)
                if ds >= start && ds < end {
                    total += byDay[ds] ?? 0
                }
            }
            if total > bestTotal {
                bestTotal = total
                bestLabel = weekLabel(cursor)
            }
            cursor = cal.date(byAdding: .day, value: 7, to: cursor) ?? cursor.addingTimeInterval(7 * 86_400)
        }

        guard bestTotal >= 0 else { return nil }
        return BestWeek(total: bestTotal, label: bestLabel)
    }

    private struct ConsistentMonth {
        var hit: Int
        var eligible: Int
        var rate: Double
        var label: String
    }

    private func mostConsistentMonth() -> ConsistentMonth? {
        let byDay: [Date: Int] = Dictionary(uniqueKeysWithValues: history.days.map { ($0.dayStart, $0.steps) })

        var best: ConsistentMonth?

        for m in 1...12 {
            guard let monthStart = cal.date(from: DateComponents(year: year, month: m, day: 1)),
                  let interval = cal.dateInterval(of: .month, for: monthStart) else { continue }

            var eligible = 0
            var hit = 0

            var d = cal.startOfDay(for: interval.start)
            while d < interval.end {
                let goal = schedule.goalSteps(for: d, calendar: cal)
                if goal > 0 {
                    eligible += 1
                    if (byDay[d] ?? 0) >= goal { hit += 1 }
                }
                d = cal.date(byAdding: .day, value: 1, to: d) ?? d.addingTimeInterval(86_400)
            }

            guard eligible > 0 else { continue }
            let rate = Double(hit) / Double(eligible)
            let label = monthLabel(monthStart)
            let candidate = ConsistentMonth(hit: hit, eligible: eligible, rate: rate, label: label)

            if let bestExisting = best {
                if candidate.rate > bestExisting.rate {
                    best = candidate
                } else if candidate.rate == bestExisting.rate && candidate.eligible > bestExisting.eligible {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }

        return best
    }

    private func startOfWeek(_ date: Date) -> Date {
        let d = cal.startOfDay(for: date)
        let weekday = cal.component(.weekday, from: d)
        let delta = (weekday - cal.firstWeekday + 7) % 7
        return cal.date(byAdding: .day, value: -delta, to: d) ?? d
    }

    private func weekLabel(_ weekStart: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = cal.timeZone
        df.dateFormat = "d MMM"
        let end = cal.date(byAdding: .day, value: 6, to: weekStart) ?? weekStart
        return "\(df.string(from: weekStart)) – \(df.string(from: end))"
    }

    private func monthLabel(_ monthStart: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = cal.timeZone
        df.dateFormat = "LLLL"
        return df.string(from: monthStart)
    }
}

private struct HeatmapCell: View {
    let dayStart: Date
    let inYear: Bool
    let steps: Int
    let goal: Int
    let size: CGFloat
    var onTap: () -> Void

    private var intensity: Double {
        guard inYear else { return 0.0 }
        guard goal > 0 else { return 0.10 }
        let f = Double(steps) / Double(goal)
        switch f {
        case ..<0.10: return 0.10
        case ..<0.35: return 0.25
        case ..<0.60: return 0.40
        case ..<1.00: return 0.60
        default: return 0.85
        }
    }

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(inYear ? Color.accentColor.opacity(intensity) : Color.clear)
            .frame(width: size, height: size)
            .onTapGesture { if inYear { onTap() } }
    }
}

// MARK: - Today card + ring

private struct StepsTodayCard: View {
    let steps: Int
    let goal: Int
    let fraction: Double
    let percent: Int
    let access: WidgetWeaverStepsAccess
    let fetchedAt: Date?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                StepsRing(fraction: fraction, lineWidth: 10)
                    .frame(width: 56, height: 56)

                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .bold()

                    Text(primary)
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()

                    Text(secondary)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }

            if let fetchedAt {
                Text("Updated \(wwTimeShort(fetchedAt))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var title: String {
        switch access {
        case .authorised: return "Steps today"
        case .denied: return "Steps (Denied)"
        case .notAvailable: return "Steps (Unavailable)"
        case .notDetermined: return "Steps (Not enabled)"
        case .unknown: return "Steps"
        }
    }

    private var primary: String {
        switch access {
        case .authorised, .unknown:
            return wwFormatSteps(steps)
        case .denied, .notAvailable, .notDetermined:
            return "—"
        }
    }

    private var secondary: String {
        switch access {
        case .denied, .notDetermined:
            return "Tap Request Steps Access."
        case .notAvailable:
            return "HealthKit isn’t available on this device."
        case .unknown, .authorised:
            if goal > 0 { return "Goal \(wwFormatSteps(goal)) • \(percent)%" }
            return "No goal set"
        }
    }
}

private struct StepsRing: View {
    let fraction: Double
    let lineWidth: CGFloat

    var body: some View {
        let clamped = min(1.0, max(0.0, fraction))
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.18), style: StrokeStyle(lineWidth: lineWidth))
            Circle()
                .trim(from: 0, to: clamped)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Formatting helpers

private func wwFormatSteps(_ n: Int) -> String {
    let nf = NumberFormatter()
    nf.numberStyle = .decimal
    nf.usesGroupingSeparator = true
    return nf.string(from: NSNumber(value: n)) ?? "\(n)"
}

private func wwDateMedium(_ d: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.autoupdatingCurrent
    df.timeZone = Calendar.autoupdatingCurrent.timeZone
    df.dateStyle = .medium
    df.timeStyle = .none
    return df.string(from: d)
}

private func wwMonthTitle(_ d: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.autoupdatingCurrent
    df.timeZone = Calendar.autoupdatingCurrent.timeZone
    df.dateFormat = "LLLL yyyy"
    return df.string(from: d)
}

private func wwTimeShort(_ d: Date) -> String {
    let df = DateFormatter()
    df.locale = Locale.autoupdatingCurrent
    df.timeZone = Calendar.autoupdatingCurrent.timeZone
    df.dateStyle = .none
    df.timeStyle = .short
    return df.string(from: d)
}
