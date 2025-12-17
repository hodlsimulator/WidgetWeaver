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
        WidgetWeaverSpecView(spec: entry.spec, family: family, context: .widget)
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
