//
//  WidgetWeaverRemindersDebugSpikeWidget.swift
//  WidgetWeaver
//
//  Created by . . on 1/15/26.
//

#if DEBUG

import Foundation
import SwiftUI
import WidgetKit

public struct WidgetWeaverRemindersDebugSpikeWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWeaverWidgetKinds.remindersDebugSpike, provider: Provider()) { entry in
            WidgetWeaverRemindersDebugSpikeView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Reminders Spike")
        .description("Debug widget that runs an AppIntent to complete a known reminder ID.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

public struct WidgetWeaverRemindersDebugSpikeEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WidgetWeaverRemindersDebugSnapshot

    public init(date: Date, snapshot: WidgetWeaverRemindersDebugSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

extension WidgetWeaverRemindersDebugSpikeWidget {
    struct Provider: TimelineProvider {
        typealias Entry = WidgetWeaverRemindersDebugSpikeEntry

        func placeholder(in context: Context) -> Entry {
            Entry(
                date: Date(),
                snapshot: WidgetWeaverRemindersDebugSnapshot(
                    testReminderID: "TEST-REMINDER-ID",
                    lastActionKind: "completed",
                    lastActionMessage: "Completed: Buy milk.",
                    lastActionAt: Date()
                )
            )
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            let snap = context.isPreview ? placeholder(in: context).snapshot : WidgetWeaverRemindersDebugStore.load()
            completion(Entry(date: Date(), snapshot: snap))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let snap = context.isPreview ? placeholder(in: context).snapshot : WidgetWeaverRemindersDebugStore.load()
            let now = Date()
            completion(Timeline(entries: [Entry(date: now, snapshot: snap)], policy: .after(now.addingTimeInterval(60 * 60))))
        }
    }
}

private struct WidgetWeaverRemindersDebugSpikeView: View {
    let entry: WidgetWeaverRemindersDebugSpikeEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let snap = entry.snapshot

        VStack(alignment: .leading, spacing: 10) {
            header

            if let id = snap.testReminderID, !id.isEmpty {
                activeContent(reminderID: id, snapshot: snap)
            } else {
                emptyContent
            }

            Spacer(minLength: 0)

            if let msg = snap.lastActionMessage, !msg.isEmpty {
                lastAction(message: msg, at: snap.lastActionAt)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Label("Reminders", systemImage: "checklist")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text("Debug")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.quaternary, in: Capsule())
        }
    }

    private func activeContent(reminderID: String, snapshot: WidgetWeaverRemindersDebugSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Test reminder ID set")
                .font(family == .systemSmall ? .headline : .title3)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text("ID: \(shortID(reminderID))")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Button(intent: WidgetWeaverCompleteReminderIntent(reminderID: reminderID)) {
                Label("Complete", systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .labelStyle(.titleAndIcon)
        }
    }

    private var emptyContent: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("No test reminder ID")
                .font(.headline)
                .fontWeight(.semibold)
                .lineLimit(1)

            Text("Open WidgetWeaver → Reminders → Load Today sample, then long-press a row and set it as the widget test ID.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(family == .systemSmall ? 4 : 5)
        }
    }

    private func lastAction(message: String, at: Date?) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.caption2)
                .foregroundStyle(.secondary)

            Text(message)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Spacer(minLength: 0)

            if let at {
                Text(at, style: .time)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func shortID(_ id: String) -> String {
        let trimmed = id.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count > 10 else { return trimmed }
        let start = trimmed.prefix(4)
        let end = trimmed.suffix(4)
        return "\(start)…\(end)"
    }
}

#endif
