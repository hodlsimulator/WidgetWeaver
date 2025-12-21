//
//  WidgetWeaverStepsWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/19/25.
//

import WidgetKit
import SwiftUI

// MARK: - Lock Screen Steps

public struct WidgetWeaverLockScreenStepsEntry: TimelineEntry {
    public let date: Date
    public let access: WidgetWeaverStepsAccess
    public let snapshot: WidgetWeaverStepsSnapshot?
    public let goal: Int

    public init(date: Date, access: WidgetWeaverStepsAccess, snapshot: WidgetWeaverStepsSnapshot?, goal: Int) {
        self.date = date
        self.access = access
        self.snapshot = snapshot
        self.goal = goal
    }
}

struct WidgetWeaverLockScreenStepsProvider: TimelineProvider {
    typealias Entry = WidgetWeaverLockScreenStepsEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), access: .authorised, snapshot: .sample(), goal: 10_000)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let store = WidgetWeaverStepsStore.shared
        let goal = store.loadGoalSteps()
        let access: WidgetWeaverStepsAccess = context.isPreview ? .authorised : store.loadLastAccess()
        let snap = context.isPreview ? WidgetWeaverStepsSnapshot.sample() : store.snapshotForToday()
        completion(Entry(date: Date(), access: access, snapshot: snap, goal: goal))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        if !context.isPreview {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: false)
            }
        }

        let store = WidgetWeaverStepsStore.shared
        let goal = store.loadGoalSteps()
        let access: WidgetWeaverStepsAccess = context.isPreview ? .authorised : store.loadLastAccess()
        let snap = context.isPreview ? WidgetWeaverStepsSnapshot.sample() : store.snapshotForToday()

        let now = Date()
        let refresh = max(60, store.recommendedRefreshIntervalSeconds())
        let next = now.addingTimeInterval(refresh)

        let entry = Entry(date: now, access: access, snapshot: snap, goal: goal)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WidgetWeaverLockScreenStepsView: View {
    let entry: WidgetWeaverLockScreenStepsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.access {
            case .denied, .notDetermined, .notAvailable:
                lockedView
            case .unknown, .authorised:
                contentView
            }
        }
        .wwWidgetContainerBackground()
    }

    @ViewBuilder
    private var lockedView: some View {
        switch family {
        case .accessoryInline:
            Text("Steps: Open app")
        case .accessoryCircular:
            VStack(spacing: 2) {
                Text("—")
                    .font(.headline)
                Image(systemName: "figure.walk")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        default:
            VStack(alignment: .leading, spacing: 3) {
                Text("Steps")
                    .font(.headline)
                Text(entry.access == .denied ? "Denied" : "Open app to enable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        let goal = max(0, entry.goal)
        let steps = entry.snapshot?.steps ?? 0
        let fraction = (goal > 0) ? min(1.0, Double(steps) / Double(goal)) : 0.0

        switch family {
        case .accessoryInline:
            Text("\(formatSteps(steps)) steps")

        case .accessoryCircular:
            ZStack {
                StepsRing(fraction: fraction, lineWidth: 6)
                Text(shortSteps(steps))
                    .font(.headline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

        default:
            VStack(alignment: .leading, spacing: 3) {
                Text("\(formatSteps(steps))")
                    .font(.headline)
                    .bold()
                if goal > 0 {
                    Text("Goal \(formatSteps(goal))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text("Steps today")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func formatSteps(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func shortSteps(_ n: Int) -> String {
        if n >= 10_000 {
            let k = Double(n) / 1000.0
            return String(format: "%.0fk", k)
        }
        return "\(n)"
    }
}

struct WidgetWeaverLockScreenStepsWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.lockScreenSteps

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverLockScreenStepsProvider()) { entry in
            WidgetWeaverLockScreenStepsView(entry: entry)
        }
        .configurationDisplayName("Steps (WidgetWeaver)")
        .description("Today’s steps with goal progress.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Home Screen Steps

public struct WidgetWeaverHomeScreenStepsEntry: TimelineEntry {
    public let date: Date
    public let access: WidgetWeaverStepsAccess
    public let snapshot: WidgetWeaverStepsSnapshot?
    public let goal: Int

    public init(date: Date, access: WidgetWeaverStepsAccess, snapshot: WidgetWeaverStepsSnapshot?, goal: Int) {
        self.date = date
        self.access = access
        self.snapshot = snapshot
        self.goal = goal
    }
}

struct WidgetWeaverHomeScreenStepsProvider: TimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenStepsEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), access: .authorised, snapshot: .sample(), goal: 10_000)
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let store = WidgetWeaverStepsStore.shared
        let goal = store.loadGoalSteps()
        let access: WidgetWeaverStepsAccess = context.isPreview ? .authorised : store.loadLastAccess()
        let snap = context.isPreview ? WidgetWeaverStepsSnapshot.sample() : store.snapshotForToday()
        completion(Entry(date: Date(), access: access, snapshot: snap, goal: goal))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        if !context.isPreview {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: false)
            }
        }

        let store = WidgetWeaverStepsStore.shared
        let goal = store.loadGoalSteps()
        let access: WidgetWeaverStepsAccess = context.isPreview ? .authorised : store.loadLastAccess()
        let snap = context.isPreview ? WidgetWeaverStepsSnapshot.sample() : store.snapshotForToday()

        let now = Date()
        let refresh = max(60, store.recommendedRefreshIntervalSeconds())
        let next = now.addingTimeInterval(refresh)

        let entry = Entry(date: now, access: access, snapshot: snap, goal: goal)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WidgetWeaverHomeScreenStepsView: View {
    let entry: WidgetWeaverHomeScreenStepsEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let goal = max(0, entry.goal)
        let steps = entry.snapshot?.steps ?? 0
        let fraction = (goal > 0) ? min(1.0, Double(steps) / Double(goal)) : 0.0
        let pct = Int((fraction * 100.0).rounded())

        ZStack {
            switch entry.access {
            case .denied, .notDetermined, .notAvailable:
                locked
            case .unknown, .authorised:
                content(goal: goal, steps: steps, fraction: fraction, pct: pct)
            }
        }
        .padding(12)
    }

    @ViewBuilder
    private var locked: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "figure.walk")
                Text("Steps")
                    .font(.headline)
                    .bold()
                Spacer()
            }
            Text("Open the app to enable Steps.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func content(goal: Int, steps: Int, fraction: Double, pct: Int) -> some View {
        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    StepsRing(fraction: fraction, lineWidth: 10)
                        .frame(width: 44, height: 44)
                    Spacer()
                }
                Text(formatSteps(steps))
                    .font(.system(.title2, design: .rounded).weight(.bold))
                    .monospacedDigit()
                Text(goal > 0 ? "today • \(pct)%" : "today")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }

        case .systemMedium:
            HStack(spacing: 14) {
                StepsRing(fraction: fraction, lineWidth: 12)
                    .frame(width: 54, height: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Steps today")
                        .font(.headline)
                        .bold()
                    Text(formatSteps(steps))
                        .font(.system(.title2, design: .rounded).weight(.bold))
                        .monospacedDigit()
                    if goal > 0 {
                        Text("Goal \(formatSteps(goal)) • \(pct)%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

        default: // .systemLarge
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    StepsRing(fraction: fraction, lineWidth: 12)
                        .frame(width: 56, height: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Steps today")
                            .font(.headline)
                            .bold()
                        Text(formatSteps(steps))
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                        if goal > 0 {
                            Text("Goal \(formatSteps(goal)) • \(pct)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }

                if let updated = entry.snapshot?.fetchedAt {
                    Text("Updated \(formatTime(updated))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
        }
    }

    private func formatSteps(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatTime(_ d: Date) -> String {
        let df = DateFormatter()
        df.locale = Locale.autoupdatingCurrent
        df.timeZone = Calendar.autoupdatingCurrent.timeZone
        df.dateStyle = .none
        df.timeStyle = .short
        return df.string(from: d)
    }
}

struct WidgetWeaverHomeScreenStepsWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.homeScreenSteps

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverHomeScreenStepsProvider()) { entry in
            WidgetWeaverHomeScreenStepsView(entry: entry)
        }
        .configurationDisplayName("Steps (Home)")
        .description("Today’s steps with a clean goal ring.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Shared ring + background

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

private extension View {
    @ViewBuilder
    func wwWidgetContainerBackground() -> some View {
        if #available(iOS 17.0, *) {
            self.containerBackground(for: .widget) { Color.clear }
        } else {
            self
        }
    }
}
