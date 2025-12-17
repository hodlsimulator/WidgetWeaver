//
//  WidgetWeaverWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/17/25.
//

import WidgetKit
import SwiftUI

struct WidgetWeaverEntry: TimelineEntry {
    let date: Date
    let spec: WidgetSpec
}

struct WidgetWeaverProvider: TimelineProvider {
    func placeholder(in context: Context) -> WidgetWeaverEntry {
        WidgetWeaverEntry(date: Date(), spec: .defaultSpec())
    }

    func getSnapshot(in context: Context, completion: @escaping (WidgetWeaverEntry) -> Void) {
        let spec = WidgetSpecStore.shared.load()
        completion(WidgetWeaverEntry(date: Date(), spec: spec))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WidgetWeaverEntry>) -> Void) {
        let spec = WidgetSpecStore.shared.load()
        let entry = WidgetWeaverEntry(date: Date(), spec: spec)
        completion(Timeline(entries: [entry], policy: .never))
    }
}

struct WidgetWeaverWidgetView: View {
    let entry: WidgetWeaverEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(entry.spec.name)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)

            Text(entry.spec.primaryText)
                .font(primaryFont)
                .foregroundStyle(.primary)
                .lineLimit(primaryLineLimit)

            if let secondary = entry.spec.secondaryText, showSecondary {
                Text(secondary)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(.fill.tertiary, for: .widget)
        .padding(12)
    }

    private var showSecondary: Bool {
        switch family {
        case .systemSmall:
            return false
        default:
            return true
        }
    }

    private var primaryFont: Font {
        switch family {
        case .systemSmall:
            return .headline
        case .systemMedium:
            return .title3
        case .systemLarge:
            return .title2
        default:
            return .headline
        }
    }

    private var primaryLineLimit: Int {
        switch family {
        case .systemSmall:
            return 2
        default:
            return 3
        }
    }
}

struct WidgetWeaverWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.main

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WidgetWeaverProvider()) { entry in
            WidgetWeaverWidgetView(entry: entry)
        }
        .configurationDisplayName("WidgetWeaver")
        .description("Renders the latest saved WidgetWeaver spec.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    WidgetWeaverWidget()
} timeline: {
    WidgetWeaverEntry(date: .now, spec: .defaultSpec())
}
