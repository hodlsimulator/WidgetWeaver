//
//  WidgetWeaverStepsSettingsView.swift
//  WidgetWeaver
//
//  Created by . . on 12/19/25.
//

import SwiftUI
import WidgetKit

@MainActor
struct WidgetWeaverStepsSettingsView: View {
    let onClose: () -> Void

    @AppStorage(WidgetWeaverStepsStore.Keys.goalSteps, store: AppGroup.userDefaults)
    private var goalSteps: Int = 10_000

    @State private var snapshot: WidgetWeaverStepsSnapshot?
    @State private var history: WidgetWeaverStepsHistorySnapshot?
    @State private var access: WidgetWeaverStepsAccess = .unknown
    @State private var lastError: String?

    @State private var isUpdatingToday: Bool = false
    @State private var statusMessage: String?

    var body: some View {
        List {
            Section {
                todayCard
                    .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
            } header: {
                Text("Today")
            }

            Section("Goal") {
                Stepper(value: $goalSteps, in: 0...100_000, step: 250) {
                    HStack {
                        Text("Daily goal")
                        Spacer()
                        Text(formatNumber(goalSteps))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }
                .onChange(of: goalSteps) { _, newValue in
                    WidgetWeaverStepsStore.shared.saveGoalSteps(newValue)
                    reloadWidgets()
                }
            }

            Section("Access") {
                HStack {
                    Text("Status")
                    Spacer()
                    Text(accessLabel(access))
                        .foregroundStyle(accessTint(access))
                }

                if let lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    Task { await requestAccessAndRefresh() }
                } label: {
                    Label("Request Steps Access", systemImage: "hand.raised.fill")
                }

                Button {
                    Task { await refreshToday(force: true) }
                } label: {
                    Label("Refresh Today", systemImage: "arrow.clockwise")
                }
                .disabled(isUpdatingToday)

                if let statusMessage, !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            Section("History") {
                NavigationLink {
                    WidgetWeaverStepsHistoryView(goalSteps: $goalSteps)
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Label("Timeline & Insights", systemImage: "clock.arrow.circlepath")
                            Spacer()
                            if let history {
                                Text("\(formatNumber(history.dayCount)) days")
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                            }
                        }

                        if let history {
                            Text("\(formatDate(history.earliestDay)) → \(formatDate(history.latestDay))")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Loads back to the first step sample (years if available).")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Button(role: .destructive) {
                    Task { await clearHistoryCache() }
                } label: {
                    Label("Clear Cached History", systemImage: "trash")
                }
            }
        }
        .navigationTitle("Steps")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { onClose() }
            }
        }
        .onAppear {
            if goalSteps <= 0 {
                goalSteps = WidgetWeaverStepsStore.shared.loadGoalSteps()
            }
            reloadFromStore()
            Task { await refreshToday(force: false) }
        }
    }

    // MARK: - UI

    private var todayCard: some View {
        let goal = max(0, goalSteps)
        let steps = snapshot?.steps ?? 0
        let fraction = (goal > 0) ? min(1.0, Double(steps) / Double(goal)) : 0.0
        let percent = Int((fraction * 100.0).rounded())
        let updated = snapshot?.fetchedAt

        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 14) {
                StepsRing(fraction: fraction, lineWidth: 10)
                    .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatNumber(steps))")
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()

                    Text(goal > 0 ? "steps today • \(percent)%" : "steps today")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)

                if isUpdatingToday {
                    ProgressView()
                }
            }

            HStack {
                Text(goal > 0 ? "Goal \(formatNumber(goal))" : "No goal set")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let updated {
                    Text("Updated \(formatTime(updated))")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        }
    }

    // MARK: - Actions

    private func reloadFromStore() {
        let store = WidgetWeaverStepsStore.shared
        snapshot = store.snapshotForToday()
        history = store.loadHistory()
        access = store.loadLastAccess()
        lastError = store.loadLastError()

        if access == .unknown, snapshot != nil {
            access = .authorised
        }
    }

    private func requestAccessAndRefresh() async {
        statusMessage = nil
        let granted = await WidgetWeaverStepsEngine.shared.requestReadAuthorisation()
        _ = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: true)

        reloadFromStore()
        reloadWidgets()

        statusMessage = granted ? "Access request completed." : "Access request failed or was declined."
    }

    private func refreshToday(force: Bool) async {
        isUpdatingToday = true
        statusMessage = nil

        _ = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: force)

        isUpdatingToday = false
        reloadFromStore()
        reloadWidgets()

        if let snap = snapshot {
            statusMessage = "Updated at \(formatTime(snap.fetchedAt))."
        }
    }

    private func clearHistoryCache() async {
        WidgetWeaverStepsEngine.shared.clearCachedHistory()
        reloadFromStore()
        reloadWidgets()
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.lockScreenSteps)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.homeScreenSteps)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }

    // MARK: - Formatting helpers

    private func formatNumber(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = Calendar.autoupdatingCurrent.timeZone
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: d)
    }

    private func formatTime(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = Calendar.autoupdatingCurrent.timeZone
        df.dateStyle = .none
        df.timeStyle = .short
        return df.string(from: d)
    }

    private func accessLabel(_ a: WidgetWeaverStepsAccess) -> String {
        switch a {
        case .unknown: return "Unknown"
        case .notAvailable: return "Not available"
        case .notDetermined: return "Not granted"
        case .denied: return "Denied"
        case .authorised: return "Granted"
        }
    }

    private func accessTint(_ a: WidgetWeaverStepsAccess) -> Color {
        switch a {
        case .authorised: return .green
        case .denied: return .red
        case .notDetermined: return .orange
        case .notAvailable: return .secondary
        case .unknown: return .secondary
        }
    }
}

// MARK: - History screen

@MainActor
private struct WidgetWeaverStepsHistoryView: View {
    @Binding var goalSteps: Int

    @State private var history: WidgetWeaverStepsHistorySnapshot?
    @State private var access: WidgetWeaverStepsAccess = .unknown
    @State private var lastError: String?

    @State private var isLoading: Bool = false
    @State private var statusMessage: String?

    @State private var range: TimelineRange = .all
    @State private var goalHitsOnly: Bool = false
    @State private var searchText: String = ""

    @State private var scrollTarget: Date?

    private enum TimelineRange: String, CaseIterable, Identifiable {
        case all
        case year1
        case days90
        case days30
        case days7

        var id: String { rawValue }

        var title: String {
            switch self {
            case .all: return "All"
            case .year1: return "1Y"
            case .days90: return "90D"
            case .days30: return "30D"
            case .days7: return "7D"
            }
        }

        func startDate(now: Date) -> Date? {
            let cal = Calendar.autoupdatingCurrent
            let today = cal.startOfDay(for: now)
            switch self {
            case .all: return nil
            case .year1: return cal.date(byAdding: .day, value: -364, to: today)
            case .days90: return cal.date(byAdding: .day, value: -89, to: today)
            case .days30: return cal.date(byAdding: .day, value: -29, to: today)
            case .days7: return cal.date(byAdding: .day, value: -6, to: today)
            }
        }
    }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    historyHeaderCard
                        .listRowInsets(EdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 10))
                }

                Section("Filters") {
                    Picker("Range", selection: $range) {
                        ForEach(TimelineRange.allCases) { r in
                            Text(r.title).tag(r)
                        }
                    }
                    .pickerStyle(.segmented)

                    Toggle("Goal hits only", isOn: $goalHitsOnly)
                }

                Section("Insights") {
                    insightsRows
                }

                if let onThisDay = onThisDayRows, !onThisDay.isEmpty {
                    Section("On this day") {
                        ForEach(onThisDay, id: \.year) { item in
                            HStack {
                                Text("\(item.year)")
                                Spacer()
                                Text(formatNumber(item.steps))
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Timeline") {
                    if isLoading {
                        HStack {
                            ProgressView()
                            Text("Loading full history…")
                                .foregroundStyle(.secondary)
                        }
                    } else if filteredPoints.isEmpty {
                        Text("No matching days.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(filteredPoints) { p in
                            StepsDayRow(
                                point: p,
                                goal: goalSteps,
                                isToday: isToday(p.dayStart)
                            )
                            .id(p.dayStart)
                        }
                    }
                }
            }
            .navigationTitle("History")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search (year or steps)")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Today") {
                            scrollTarget = Calendar.autoupdatingCurrent.startOfDay(for: Date())
                        }
                        if let earliest = history?.earliestDay {
                            Button("Earliest") { scrollTarget = earliest }
                        }
                        Divider()
                        ForEach(availableYears, id: \.self) { y in
                            Button("\(y)") {
                                if let d = firstDay(in: y) { scrollTarget = d }
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.and.down.text.horizontal")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshFullHistory(force: true) }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(isLoading)
                }
            }
            .onAppear {
                reloadFromStore()
                Task { await refreshFullHistory(force: false) }
            }
            .onChange(of: scrollTarget) { _, newValue in
                guard let d = newValue else { return }
                withAnimation(.easeInOut(duration: 0.25)) {
                    proxy.scrollTo(d, anchor: .top)
                }
            }
        }
    }

    // MARK: - Derived

    private var analytics: WidgetWeaverStepsAnalytics? {
        guard let history else { return nil }
        return WidgetWeaverStepsAnalytics(history: history, goal: goalSteps, now: Date())
    }

    private var availableYears: [Int] {
        guard let history else { return [] }
        let cal = Calendar.autoupdatingCurrent
        let years = Set(history.days.map { cal.component(.year, from: $0.dayStart) })
        return years.sorted(by: >)
    }

    private func firstDay(in year: Int) -> Date? {
        guard let history else { return nil }
        let cal = Calendar.autoupdatingCurrent
        return history.days.first(where: { cal.component(.year, from: $0.dayStart) == year })?.dayStart
    }

    private var filteredPoints: [WidgetWeaverStepsDayPoint] {
        guard let history else { return [] }

        let cal = Calendar.autoupdatingCurrent
        let now = Date()
        let today = cal.startOfDay(for: now)
        let startLimit = range.startDate(now: now)

        var points = history.days

        if let startLimit {
            points = points.filter { $0.dayStart >= startLimit && $0.dayStart <= today }
        }

        if goalHitsOnly, goalSteps > 0 {
            points = points.filter { $0.steps >= goalSteps }
        }

        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            points = points.filter { p in
                let y = cal.component(.year, from: p.dayStart)
                let yearMatch = "\(y)".contains(trimmed)
                let stepsMatch = "\(p.steps)".contains(trimmed.replacingOccurrences(of: ",", with: ""))
                return yearMatch || stepsMatch
            }
        }

        return points.sorted { $0.dayStart > $1.dayStart }
    }

    private var onThisDayRows: [(year: Int, steps: Int)]? {
        analytics?.stepsOnThisDayByYear()
    }

    // MARK: - UI bits

    private var historyHeaderCard: some View {
        let goal = max(0, goalSteps)
        let todaySteps = WidgetWeaverStepsStore.shared.snapshotForToday()?.steps ?? 0
        let frac = (goal > 0) ? min(1.0, Double(todaySteps) / Double(goal)) : 0.0
        let pct = Int((frac * 100.0).rounded())

        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                StepsRing(fraction: frac, lineWidth: 10)
                    .frame(width: 42, height: 42)

                VStack(alignment: .leading, spacing: 2) {
                    Text("\(formatNumber(todaySteps))")
                        .font(.system(.title3, design: .rounded).weight(.bold))
                        .monospacedDigit()

                    Text(goal > 0 ? "today • \(pct)%" : "today")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                if isLoading {
                    ProgressView()
                }
            }

            if let history {
                Text("\(formatDate(history.earliestDay)) → \(formatDate(history.latestDay)) • \(formatNumber(history.dayCount)) days")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            } else {
                Text("Tap refresh to fetch full history back to the first step sample.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Text("Access: \(accessLabel(access))")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
                if let lastError, !lastError.isEmpty {
                    Text(lastError)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let statusMessage, !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .background {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(uiColor: .secondarySystemBackground))
        }
    }

    private var insightsRows: some View {
        Group {
            if let analytics, let best = analytics.bestDay {
                HStack {
                    Text("Best day")
                    Spacer()
                    Text("\(formatDateShort(best.dayStart)) • \(formatNumber(best.steps))")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            } else {
                Text("Insights appear after history is loaded.")
                    .foregroundStyle(.secondary)
            }

            if let analytics {
                HStack {
                    Text("7‑day average")
                    Spacer()
                    Text(formatNumber(Int(analytics.averageSteps(days: 7).rounded())))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("30‑day average")
                    Spacer()
                    Text(formatNumber(Int(analytics.averageSteps(days: 30).rounded())))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                HStack {
                    Text("Goal streak")
                    Spacer()
                    Text("\(analytics.currentGoalStreakDays) days")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - Actions

    private func reloadFromStore() {
        let store = WidgetWeaverStepsStore.shared
        history = store.loadHistory()
        access = store.loadLastAccess()
        lastError = store.loadLastError()
        if access == .unknown, store.snapshotForToday() != nil {
            access = .authorised
        }
    }

    private func refreshFullHistory(force: Bool) async {
        isLoading = true
        statusMessage = nil

        _ = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: force)
        _ = await WidgetWeaverStepsEngine.shared.updateHistoryFromBeginningIfNeeded(force: force)

        reloadFromStore()
        reloadWidgets()

        isLoading = false

        if let history {
            statusMessage = "Loaded \(formatNumber(history.dayCount)) days."
        } else {
            statusMessage = "No history available yet."
        }
    }

    private func reloadWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.lockScreenSteps)
        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.homeScreenSteps)
        WidgetCenter.shared.reloadAllTimelines()
        if #available(iOS 17.0, *) {
            WidgetCenter.shared.invalidateConfigurationRecommendations()
        }
    }

    // MARK: - Helpers

    private func isToday(_ d: Date) -> Bool {
        let cal = Calendar.autoupdatingCurrent
        return cal.isDateInToday(d)
    }

    private func accessLabel(_ a: WidgetWeaverStepsAccess) -> String {
        switch a {
        case .unknown: return "Unknown"
        case .notAvailable: return "Not available"
        case .notDetermined: return "Not granted"
        case .denied: return "Denied"
        case .authorised: return "Granted"
        }
    }

    private func formatNumber(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatDate(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = Calendar.autoupdatingCurrent.timeZone
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: d)
    }

    private func formatDateShort(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = Calendar.autoupdatingCurrent.timeZone
        df.dateStyle = .short
        df.timeStyle = .none
        return df.string(from: d)
    }
}

private struct StepsDayRow: View {
    let point: WidgetWeaverStepsDayPoint
    let goal: Int
    let isToday: Bool

    var body: some View {
        let hit = (goal > 0) ? (point.steps >= goal) : false
        let fraction = (goal > 0) ? min(1.0, Double(point.steps) / Double(goal)) : 0.0

        HStack(spacing: 12) {
            StepsRing(fraction: fraction, lineWidth: 6)
                .frame(width: 26, height: 26)
                .opacity(goal > 0 ? 1.0 : 0.35)

            VStack(alignment: .leading, spacing: 2) {
                Text(dateLine(point.dayStart, isToday: isToday))
                    .font(.subheadline.weight(.semibold))
                Text(hit ? "Goal hit" : (goal > 0 ? "Goal missed" : "No goal"))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            Text(formatNumber(point.steps))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
    }

    private func dateLine(_ d: Date, isToday: Bool) -> String {
        if isToday { return "Today" }
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = Calendar.autoupdatingCurrent.timeZone
        df.dateStyle = .medium
        df.timeStyle = .none
        return df.string(from: d)
    }

    private func formatNumber(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

// MARK: - Ring

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
        .accessibilityLabel("Progress")
        .accessibilityValue("\(Int((clamped * 100.0).rounded())) percent")
    }
}
