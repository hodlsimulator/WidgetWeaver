//
//  WidgetWeaverWidget.swift
//  WidgetWeaverWidget
//
//  Created by Conor on 12/17/25.
//

import WidgetKit
import SwiftUI

struct WidgetWeaverWidgetEntry: TimelineEntry {
    let date: Date
    let spec: WidgetSpec
}

struct WidgetWeaverWidgetProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverWidgetEntry
    typealias Intent = WidgetWeaverSelectDesignIntent

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), spec: .defaultSpec().resolved(for: context.family))
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let spec = loadSpec(for: configuration)

        if spec.usesWeatherRendering() {
            _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded()
        }

        return Entry(date: Date(), spec: spec)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let spec = loadSpec(for: configuration)

        if spec.usesWeatherRendering() {
            _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded()
        }

        var refreshSeconds: TimeInterval = 60 * 15

        if spec.usesWeatherRendering() {
            refreshSeconds = WidgetWeaverWeatherStore.shared.recommendedRefreshIntervalSeconds()
        }

        if spec.usesTimeDependentRendering() {
            refreshSeconds = 60 * 5
        }

        let entry = Entry(date: Date(), spec: spec)
        let next = Date().addingTimeInterval(refreshSeconds)
        return Timeline(entries: [entry], policy: .after(next))
    }

    private func loadSpec(for configuration: Intent) -> WidgetSpec {
        let store = WidgetSpecStore.shared

        if let designId = configuration.design?.id, let spec = store.loadDesign(id: designId) {
            return spec
        }

        if let spec = store.loadAllDesigns().first {
            return spec
        }

        return .defaultSpec()
    }
}

struct WidgetWeaverWidgetView: View {
    let entry: WidgetWeaverWidgetProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetWeaverSpecView(spec: entry.spec, family: family, context: .widget)
    }
}

struct WidgetWeaverWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetWeaverWidgetKinds.designWidget,
            intent: WidgetWeaverSelectDesignIntent.self,
            provider: WidgetWeaverWidgetProvider()
        ) { entry in
            WidgetWeaverWidgetView(entry: entry)
        }
        .configurationDisplayName("Design")
        .description("A WidgetWeaver design.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}
