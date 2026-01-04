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
        ZStack {
            switch entry.access {
            case .denied, .notDetermined, .notAvailable:
                locked
            case .unknown, .authorised:
                content
            }
        }
        .padding(12)
        .wwWidgetContainerBackground()
    }

    @ViewBuilder
    private var locked: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                Text("Steps")
                    .font(.headline)
                    .bold()
                Spacer()
            }

            Text(entry.access == .denied ? "Denied" : "Open the app to enable Health access.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    @ViewBuilder
    private var content: some View {
        let snap = entry.snapshot
        let goal = max(0, entry.goal)

        let steps = snap?.steps ?? 0

        let fraction: Double = {
            guard goal > 0 else { return 0.0 }
            return min(1.0, Double(steps) / Double(goal))
        }()

        let pct: Int? = {
            guard goal > 0 else { return nil }
            return Int((min(1.0, Double(steps) / Double(goal)) * 100.0).rounded())
        }()

        let stepsText = formatSteps(steps)
        let goalText = (goal > 0) ? formatSteps(goal) : nil

        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.headline)
                    Text("Steps")
                        .font(.headline)
                        .bold()
                    Spacer(minLength: 0)
                    if let updatedAt = snap?.fetchedAt {
                        Text(formatTime(updatedAt))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        StepsRing(fraction: fraction, lineWidth: 10)
                        Text(pct.map { "\($0)%" } ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stepsText)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(goalText.map { "Goal \($0)" } ?? "Steps today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                Spacer()
            }

        case .systemMedium:
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.headline)
                    Text("Steps")
                        .font(.headline)
                        .bold()
                    Spacer(minLength: 0)
                    if let updatedAt = snap?.fetchedAt {
                        Text(formatTime(updatedAt))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        StepsRing(fraction: fraction, lineWidth: 12)
                        Image(systemName: "figure.walk")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(width: 60, height: 60)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stepsText)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        if let goalText, let pct {
                            Text("Goal \(goalText) • \(pct)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Steps today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }

                Spacer(minLength: 0)
            }

        default: // .systemLarge and others
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "figure.walk")
                        .font(.headline)
                    Text("Steps")
                        .font(.headline)
                        .bold()
                    Spacer(minLength: 0)
                    if let updatedAt = snap?.fetchedAt {
                        Text(formatTime(updatedAt))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        StepsRing(fraction: fraction, lineWidth: 12)
                        Text(pct.map { "\($0)%" } ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 66, height: 66)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stepsText)
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        if let goalText, let pct {
                            Text("Goal \(goalText) • \(pct)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Steps today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
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
        .description("A clean steps snapshot for today.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

// MARK: - Lock Screen Activity (multi-metric)

public struct WidgetWeaverLockScreenActivityEntry: TimelineEntry {
    public let date: Date
    public let access: WidgetWeaverActivityAccess
    public let snapshot: WidgetWeaverActivitySnapshot?

    public init(date: Date, access: WidgetWeaverActivityAccess, snapshot: WidgetWeaverActivitySnapshot?) {
        self.date = date
        self.access = access
        self.snapshot = snapshot
    }
}

struct WidgetWeaverLockScreenActivityProvider: TimelineProvider {
    typealias Entry = WidgetWeaverLockScreenActivityEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), access: .authorised, snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let store = WidgetWeaverActivityStore.shared
        let access: WidgetWeaverActivityAccess = context.isPreview ? .authorised : store.loadLastAccess()
        let snap = context.isPreview ? WidgetWeaverActivitySnapshot.sample() : store.snapshotForToday()
        completion(Entry(date: Date(), access: access, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        if !context.isPreview {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverActivityEngine.shared.updateIfNeeded(force: false)
            }
        }

        let store = WidgetWeaverActivityStore.shared
        let access: WidgetWeaverActivityAccess = context.isPreview ? .authorised : store.loadLastAccess()
        let snap = context.isPreview ? WidgetWeaverActivitySnapshot.sample() : store.snapshotForToday()

        let now = Date()
        let refresh = max(60, store.recommendedRefreshIntervalSeconds())
        let next = now.addingTimeInterval(refresh)

        let entry = Entry(date: now, access: access, snapshot: snap)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WidgetWeaverLockScreenActivityView: View {
    let entry: WidgetWeaverLockScreenActivityEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            switch entry.access {
            case .denied, .notDetermined, .notAvailable:
                lockedView
            case .unknown, .authorised, .partial:
                contentView
            }
        }
        .wwWidgetContainerBackground()
    }

    @ViewBuilder
    private var lockedView: some View {
        switch family {
        case .accessoryInline:
            Text("Activity: Open app")

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
                Text("Activity")
                    .font(.headline)
                Text(entry.access == .denied ? "Denied" : "Open app to enable")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var contentView: some View {
        let snap = entry.snapshot
        let goal = max(0, WidgetWeaverStepsStore.shared.loadGoalSteps())
        let steps = snap?.steps

        let fraction: Double = {
            guard let steps, goal > 0 else { return 0.0 }
            return min(1.0, Double(steps) / Double(goal))
        }()

        switch family {
        case .accessoryInline:
            if let steps {
                if let meters = snap?.distanceWalkingRunningMeters {
                    Text("\(formatSteps(steps)) • \(formatDistanceKMShort(meters))")
                } else if let kcal = snap?.activeEnergyBurnedKilocalories {
                    Text("\(formatSteps(steps)) • \(formatKcalShort(kcal))")
                } else if let flights = snap?.flightsClimbed {
                    Text("\(formatSteps(steps)) • \(flights) fl")
                } else {
                    Text("\(formatSteps(steps)) steps")
                }
            } else {
                Text("Activity")
            }

        case .accessoryCircular:
            ZStack {
                StepsRing(fraction: fraction, lineWidth: 6)
                Text(steps.map(shortSteps) ?? "—")
                    .font(.headline)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
            }

        default: // .accessoryRectangular
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Image(systemName: "figure.walk")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text("Activity")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Spacer(minLength: 0)
                    if entry.access == .partial {
                        Text("Partial")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(steps.map(formatSteps) ?? "—")
                    .font(.headline.weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)

                Text(compactLine(
                    flights: snap?.flightsClimbed,
                    meters: snap?.distanceWalkingRunningMeters,
                    kcal: snap?.activeEnergyBurnedKilocalories
                ))
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
    }

    private func compactLine(flights: Int?, meters: Double?, kcal: Double?) -> String {
        var parts: [String] = []
        if let meters {
            parts.append(formatDistanceKMShort(meters))
        }
        if let kcal {
            parts.append(formatKcalShort(kcal))
        }
        if let flights {
            parts.append("\(flights) fl")
        }
        return parts.isEmpty ? "Today" : parts.joined(separator: " • ")
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

    private func formatDistanceKMShort(_ meters: Double) -> String {
        let km = max(0, meters) / 1000.0
        if km >= 10 {
            return String(format: "%.0f km", km)
        } else if km >= 1 {
            return String(format: "%.1f km", km)
        } else {
            return String(format: "%.0f m", max(0, meters))
        }
    }

    private func formatKcalShort(_ kcal: Double) -> String {
        let v = max(0, Int(kcal.rounded()))
        return "\(v) kcal"
    }
}

struct WidgetWeaverLockScreenActivityWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.lockScreenActivity

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverLockScreenActivityProvider()) { entry in
            WidgetWeaverLockScreenActivityView(entry: entry)
        }
        .configurationDisplayName("Activity (WidgetWeaver)")
        .description("Steps + a few activity stats for today.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}

// MARK: - Home Screen Activity (multi-metric)

public struct WidgetWeaverHomeScreenActivityEntry: TimelineEntry {
    public let date: Date
    public let access: WidgetWeaverActivityAccess
    public let snapshot: WidgetWeaverActivitySnapshot?

    public init(date: Date, access: WidgetWeaverActivityAccess, snapshot: WidgetWeaverActivitySnapshot?) {
        self.date = date
        self.access = access
        self.snapshot = snapshot
    }
}

struct WidgetWeaverHomeScreenActivityProvider: TimelineProvider {
    typealias Entry = WidgetWeaverHomeScreenActivityEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), access: .authorised, snapshot: .sample())
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        let store = WidgetWeaverActivityStore.shared
        let access: WidgetWeaverActivityAccess = context.isPreview ? .authorised : store.loadLastAccess()
        let snap = context.isPreview ? WidgetWeaverActivitySnapshot.sample() : store.snapshotForToday()
        completion(Entry(date: Date(), access: access, snapshot: snap))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        if !context.isPreview {
            Task.detached(priority: .utility) {
                _ = await WidgetWeaverActivityEngine.shared.updateIfNeeded(force: false)
            }
        }

        let store = WidgetWeaverActivityStore.shared
        let access: WidgetWeaverActivityAccess = context.isPreview ? .authorised : store.loadLastAccess()
        let snap = context.isPreview ? WidgetWeaverActivitySnapshot.sample() : store.snapshotForToday()

        let now = Date()
        let refresh = max(60, store.recommendedRefreshIntervalSeconds())
        let next = now.addingTimeInterval(refresh)

        let entry = Entry(date: now, access: access, snapshot: snap)
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

struct WidgetWeaverHomeScreenActivityView: View {
    let entry: WidgetWeaverHomeScreenActivityEntry
    @Environment(\.widgetFamily) private var family
    
    private var headerTopInset: CGFloat {
        switch family {
        case .systemSmall, .systemMedium:
            return 4
        default:
            return 0
        }
    }

    var body: some View {
        ZStack {
            switch entry.access {
            case .denied, .notDetermined, .notAvailable:
                locked
            case .unknown, .authorised, .partial:
                content
            }
        }
        .padding(12)
        .wwWidgetContainerBackground()
    }

    // MARK: - Locked state

    @ViewBuilder
    private var locked: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "figure.walk")
                Text("Activity")
                    .font(.headline)
                    .bold()
                Spacer()
            }
            .padding(.top, headerTopInset)

            Text(entry.access == .denied ? "Denied" : "Open the app to enable Health access.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()
        }
    }

    // MARK: - Content state

    @ViewBuilder
    private var content: some View {
        let snap = entry.snapshot
        let goal = max(0, WidgetWeaverStepsStore.shared.loadGoalSteps())

        let steps = snap?.steps
        let flights = snap?.flightsClimbed
        let meters = snap?.distanceWalkingRunningMeters
        let kcal = snap?.activeEnergyBurnedKilocalories

        let fraction: Double = {
            guard let steps, goal > 0 else { return 0.0 }
            return min(1.0, Double(steps) / Double(goal))
        }()

        let pct: Int? = {
            guard let steps, goal > 0 else { return nil }
            return Int((min(1.0, Double(steps) / Double(goal)) * 100.0).rounded())
        }()

        let stepsText = steps.map(formatSteps) ?? "—"
        let goalText = (goal > 0) ? formatSteps(goal) : nil

        let distanceText = meters.map(formatDistanceKM) ?? "—"
        let energyText = kcal.map(formatKcal) ?? "—"
        let flightsText = flights.map { "\($0)" } ?? "—"
        let flightsCompactText = flights.map { "\($0) fl" } ?? "—"

        switch family {
        case .systemSmall:
            VStack(alignment: .leading, spacing: 10) {
                headerRow(updatedAt: nil)

                HStack(alignment: .center, spacing: 12) {
                    ZStack {
                        StepsRing(fraction: fraction, lineWidth: 10)
                        Text(pct.map { "\($0)%" } ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 54, height: 54)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(stepsText)
                            .font(.system(.title2, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        Text(goalText.map { "Goal \($0)" } ?? "Steps today")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 10) {
                    MetricChip(systemImage: "map", text: distanceText)
                    MetricChip(systemImage: "arrow.up", text: flightsCompactText)
                }

                Spacer(minLength: 0)

                if entry.access == .partial {
                    Text("Some metrics disabled")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                MetricPill(systemImage: "flame.fill", text: energyText)
            }

        case .systemMedium:
            VStack(alignment: .leading, spacing: 12) {
                headerRow(updatedAt: snap?.fetchedAt)

                HStack(alignment: .center, spacing: 14) {
                    HStack(alignment: .center, spacing: 12) {
                        ZStack {
                            StepsRing(fraction: fraction, lineWidth: 12)
                            Image(systemName: "figure.walk")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(width: 60, height: 60)

                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(stepsText)
                                    .font(.system(.title2, design: .rounded).weight(.bold))
                                    .monospacedDigit()
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.75)

                                if let goalText, let pct {
                                    Text("Goal \(goalText) • \(pct)%")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                } else {
                                    Text("Steps today")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                        .minimumScaleFactor(0.75)
                                }
                            }

                            MetricPill(systemImage: "map", text: distanceText)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    VStack(spacing: 10) {
                        MetricRow(systemImage: "flame.fill", title: "Active energy", value: energyText)
                        MetricRow(systemImage: "arrow.up", title: "Flights climbed", value: flightsText)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.top, 2)

                if entry.access == .partial {
                    Text("Some metrics are disabled in Health.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }

        default: // .systemLarge and others
            VStack(alignment: .leading, spacing: 12) {
                headerRow(updatedAt: snap?.fetchedAt)

                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        StepsRing(fraction: fraction, lineWidth: 12)
                        Text(pct.map { "\($0)%" } ?? "")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                    .frame(width: 66, height: 66)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(stepsText)
                            .font(.system(.title, design: .rounded).weight(.bold))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.75)

                        if let goalText, let pct {
                            Text("Goal \(goalText) • \(pct)%")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        } else {
                            Text("Steps today")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }

                LazyVGrid(
                    columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ],
                    spacing: 12
                ) {
                    MetricTile(systemImage: "map", title: "Distance", value: distanceText)
                    MetricTile(systemImage: "flame.fill", title: "Active energy", value: energyText)
                    MetricTile(systemImage: "arrow.up", title: "Flights", value: flightsText)
                    MetricTile(
                        systemImage: "clock",
                        title: "Updated",
                        value: (snap?.fetchedAt).map(formatTime) ?? "—"
                    )
                }

                if entry.access == .partial {
                    Text("Some metrics are disabled in Health.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }
        }
    }

    // MARK: - Building blocks

    private func headerRow(updatedAt: Date?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "figure.walk")
                .font(.headline)

            Text("Activity")
                .font(.headline)
                .bold()

            if entry.access == .partial {
                Badge(text: "Partial")
            }

            Spacer(minLength: 0)

            if let updatedAt {
                Text(formatTime(updatedAt))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .padding(.top, headerTopInset)
    }

    private struct Badge: View {
        let text: String

        var body: some View {
            Text(text)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 999, style: .continuous)
                        .fill(Color.secondary.opacity(0.12))
                )
        }
    }

    private struct MetricChip: View {
        let systemImage: String
        let text: String

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(Color.accentColor)

                Text(text)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.60)
                    .layoutPriority(1)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private struct MetricPill: View {
        let systemImage: String
        let text: String

        var body: some View {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color.accentColor)
                Text(text)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .fill(Color.accentColor.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 999, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.14), lineWidth: 1)
            )
        }
    }

    private struct MetricRow: View {
        let systemImage: String
        let title: String
        let value: String

        var body: some View {
            HStack(spacing: 10) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.accentColor.opacity(0.10))
                    Image(systemName: systemImage)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                }
                .frame(width: 30, height: 30)

                VStack(alignment: .leading, spacing: 2) {
                    Text(value)
                        .font(.system(.headline, design: .rounded).weight(.bold))
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)

                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer(minLength: 0)
            }
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.secondary.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .strokeBorder(Color.secondary.opacity(0.12), lineWidth: 1)
            )
        }
    }

    private struct MetricTile: View {
        let systemImage: String
        let title: String
        let value: String

        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: systemImage)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)

                    Text(title)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Spacer(minLength: 0)
                }

                Text(value)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)

                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, minHeight: 66, alignment: .topLeading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color.accentColor.opacity(0.08))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.accentColor.opacity(0.12), lineWidth: 1)
            )
        }
    }

    // MARK: - Formatting helpers

    private func formatSteps(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.usesGroupingSeparator = true
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    private func formatDistanceKM(_ meters: Double) -> String {
        let km = max(0, meters) / 1000.0
        if km >= 10 {
            return String(format: "%.0f km", km)
        }
        return String(format: "%.1f km", km)
    }

    private func formatKcal(_ kcal: Double) -> String {
        return "\(max(0, Int(kcal.rounded()))) kcal"
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

struct WidgetWeaverHomeScreenActivityWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.homeScreenActivity

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverHomeScreenActivityProvider()) { entry in
            WidgetWeaverHomeScreenActivityView(entry: entry)
        }
        .configurationDisplayName("Activity (Home)")
        .description("An activity snapshot with steps, distance, energy, and flights.")
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
    func wwWidgetContainerBackground() -> some View {
        // iOS 26-only: always adopt the widget container background API.
        self.containerBackground(.fill.tertiary, for: .widget)
    }
}
