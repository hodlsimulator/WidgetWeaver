//
//  WidgetWeaverClipboardActionsWidget.swift
//  WidgetWeaver
//
//  Created by . . on 1/13/26.
//

import Foundation
import SwiftUI
import WidgetKit

public struct WidgetWeaverClipboardActionsWidget: Widget {
    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetWeaverWidgetKinds.clipboardActions, provider: Provider()) { entry in
            WidgetWeaverClipboardActionsView(entry: entry)
        }
        .configurationDisplayName("Clipboard Actions")
        .description("Capture clipboard text and run quick actions.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

public struct WidgetWeaverClipboardEntry: TimelineEntry {
    public let date: Date
    public let snapshot: WidgetWeaverClipboardInboxSnapshot

    public init(date: Date, snapshot: WidgetWeaverClipboardInboxSnapshot) {
        self.date = date
        self.snapshot = snapshot
    }
}

extension WidgetWeaverClipboardActionsWidget {
    struct Provider: TimelineProvider {
        typealias Entry = WidgetWeaverClipboardEntry

        func placeholder(in context: Context) -> Entry {
            Entry(
                date: Date(),
                snapshot: WidgetWeaverClipboardInboxSnapshot(
                    text: "Dinner with Aoife\nTomorrow 19:30\nAt The Winding Stair",
                    capturedAt: Date(),
                    lastActionKind: "auto-event",
                    lastActionMessage: "Event created.",
                    lastActionAt: Date(),
                    lastExportedCSVPath: nil
                )
            )
        }

        func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
            let snap = context.isPreview ? placeholder(in: context).snapshot : WidgetWeaverClipboardInboxStore.load()
            completion(Entry(date: Date(), snapshot: snap))
        }

        func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
            let snap = context.isPreview ? placeholder(in: context).snapshot : WidgetWeaverClipboardInboxStore.load()
            let now = Date()
            let entry = Entry(date: now, snapshot: snap)

            // Mostly updated via WidgetCenter reloads from App Intents.
            let refresh = now.addingTimeInterval(30 * 60)
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }
}

private struct WidgetWeaverClipboardActionsView: View {
    let entry: WidgetWeaverClipboardEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            snippet

            Spacer(minLength: 0)

            if family == .systemMedium {
                mediumButtons
            } else {
                smallButtons
            }

            lastAction
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "doc.on.clipboard")
                .font(.headline)

            Text("Clipboard")
                .font(.headline)

            Spacer(minLength: 0)

            if let capturedAt = entry.snapshot.capturedAt {
                Text(capturedAt, style: .time)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var snippet: some View {
        Group {
            if let text = entry.snapshot.text {
                Text(text)
                    .font(.caption)
                    .foregroundStyle(.primary)
                    .lineLimit(family == .systemSmall ? 3 : 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Text("Tap Capture to load clipboard text.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var lastAction: some View {
        Group {
            if let msg = entry.snapshot.lastActionMessage, !msg.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "sparkles")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(msg)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 0)

                    if let at = entry.snapshot.lastActionAt {
                        Text(at, style: .time)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var smallButtons: some View {
        HStack(spacing: 10) {
            Button(intent: WidgetWeaverClipboardCaptureIntent()) {
                Label("Capture", systemImage: "arrow.down.doc")
            }
            .buttonStyle(.borderedProminent)

            Button(intent: WidgetWeaverClipboardAutoDetectIntent()) {
                Label("Auto", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
        }
        .labelStyle(.iconOnly)
    }

    private var mediumButtons: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Button(intent: WidgetWeaverClipboardCaptureIntent()) {
                    Label("Capture", systemImage: "arrow.down.doc")
                }
                .buttonStyle(.borderedProminent)

                Button(intent: WidgetWeaverClipboardAutoDetectIntent()) {
                    Label("Auto", systemImage: "wand.and.stars")
                }
                .buttonStyle(.bordered)

                Button(intent: WidgetWeaverClipboardClearInboxIntent()) {
                    Label("Clear", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            .labelStyle(.iconOnly)

            HStack(spacing: 10) {
                Button(intent: WidgetWeaverClipboardCreateReminderIntent()) {
                    Label("Reminder", systemImage: "checklist")
                }
                .buttonStyle(.bordered)

                Button(intent: WidgetWeaverClipboardCreateEventIntent()) {
                    Label("Event", systemImage: "calendar.badge.plus")
                }
                .buttonStyle(.bordered)

                Button(intent: WidgetWeaverClipboardCreateContactIntent()) {
                    Label("Contact", systemImage: "person.crop.circle.badge.plus")
                }
                .buttonStyle(.bordered)

                Button(intent: WidgetWeaverClipboardExportReceiptCSVIntent()) {
                    Label("CSV", systemImage: "tablecells")
                }
                .buttonStyle(.bordered)
            }
            .labelStyle(.iconOnly)
        }
    }
}
