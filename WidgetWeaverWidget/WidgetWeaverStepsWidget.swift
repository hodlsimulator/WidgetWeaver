//
//  WidgetWeaverStepsWidget.swift
//  WidgetWeaver
//
//  Created by . . on 12/21/25.
//

import WidgetKit
import SwiftUI
import Foundation

private final class WidgetWeaverCompletionBox<T>: @unchecked Sendable {
    let handler: (T) -> Void
    init(_ handler: @escaping (T) -> Void) {
        self.handler = handler
    }
}

public struct WidgetWeaverLockScreenStepsEntry: TimelineEntry {
    public let date: Date
    public let hasAccess: Bool
    public let snapshot: WidgetWeaverStepsSnapshot?
    public let goalSteps: Int

    public init(date: Date, hasAccess: Bool, snapshot: WidgetWeaverStepsSnapshot?, goalSteps: Int) {
        self.date = date
        self.hasAccess = hasAccess
        self.snapshot = snapshot
        self.goalSteps = goalSteps
    }
}

struct WidgetWeaverLockScreenStepsProvider: TimelineProvider {
    typealias Entry = WidgetWeaverLockScreenStepsEntry

    func placeholder(in context: Context) -> Entry {
        Entry(
            date: Date(),
            hasAccess: true,
            snapshot: .sample(steps: 7345),
            goalSteps: 10_000
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if context.isPreview {
            completion(placeholder(in: context))
            return
        }

        let store = WidgetWeaverStepsStore.shared
        let snap = store.snapshotForToday()
        let hasAccess = (snap != nil)
        completion(Entry(date: Date(), hasAccess: hasAccess, snapshot: snap, goalSteps: store.loadGoalSteps()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        let isPreview = context.isPreview
        let completionBox = WidgetWeaverCompletionBox(completion)

        Task {
            if !isPreview {
                _ = await WidgetWeaverStepsEngine.shared.updateIfNeeded(force: false)
            }

            let store = WidgetWeaverStepsStore.shared
            let now = Date()
            let snap = isPreview ? WidgetWeaverStepsSnapshot.sample(now: now, steps: 7345) : store.snapshotForToday(now: now)
            let hasAccess = isPreview ? true : (snap != nil)
            let goal = store.loadGoalSteps()

            let refresh = store.recommendedRefreshIntervalSeconds()
            let entry = Entry(date: now, hasAccess: hasAccess, snapshot: snap, goalSteps: goal)
            let timeline = Timeline(entries: [entry], policy: .after(now.addingTimeInterval(refresh)))

            completionBox.handler(timeline)
        }
    }
}

struct WidgetWeaverLockScreenStepsView: View {
    let entry: WidgetWeaverLockScreenStepsEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let snap = entry.snapshot {
                stepsView(steps: snap.stepsToday, goal: entry.goalSteps)
            } else {
                accessOffView
            }
        }
        .containerBackground(for: .widget) { Color.clear }
    }

    @ViewBuilder
    private var accessOffView: some View {
        switch family {
        case .accessoryInline:
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                Text("Open app")
            }

        case .accessoryCircular:
            VStack(spacing: 2) {
                Image(systemName: "figure.walk")
                    .font(.headline)
                Text("Open")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 3) {
                Text("Steps")
                    .font(.headline)
                Text("Open the app to enable Health access and fetch steps once.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

        default:
            Text("Open app")
        }
    }

    @ViewBuilder
    private func stepsView(steps: Int, goal: Int) -> some View {
        let stepsText = steps.formatted(.number.grouping(.automatic))
        let goalValue = max(1, goal)
        let fraction = min(1.0, Double(max(0, steps)) / Double(goalValue))
        let pct = Int((fraction * 100.0).rounded())

        switch family {
        case .accessoryInline:
            HStack(spacing: 4) {
                Image(systemName: "figure.walk")
                Text(stepsText)
            }

        case .accessoryCircular:
            Gauge(value: Double(min(steps, goalValue)), in: 0...Double(goalValue)) {
                Image(systemName: "figure.walk")
            } currentValueLabel: {
                Text(compactSteps(steps))
            }
            .gaugeStyle(.accessoryCircular)

        case .accessoryRectangular:
            VStack(alignment: .leading, spacing: 4) {
                Text(stepsText)
                    .font(.headline)
                    .bold()

                Text("steps today")
                    .font(.caption2)
                    .foregroundStyle(.secondary)

                Text("Goal \(goalValue.formatted(.number.grouping(.automatic))) • \(pct)%")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

        default:
            Text("\(stepsText) steps")
        }
    }

    private func compactSteps(_ steps: Int) -> String {
        let n = max(0, steps)
        if n < 1000 { return "\(n)" }
        if n < 10_000 {
            let v = Double(n) / 1000.0
            return String(format: "%.1fk", v)
        }
        if n < 1_000_000 {
            let v = Double(n) / 1000.0
            return String(format: "%.0fk", v)
        }
        let v = Double(n) / 1_000_000.0
        return String(format: "%.1fM", v)
    }
}

struct WidgetWeaverLockScreenStepsWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.lockScreenSteps

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverLockScreenStepsProvider()) { entry in
            WidgetWeaverLockScreenStepsView(entry: entry)
        }
        .configurationDisplayName("Steps (WidgetWeaver)")
        .description("Today’s step count with an optional goal gauge.")
        .supportedFamilies([.accessoryInline, .accessoryCircular, .accessoryRectangular])
    }
}
