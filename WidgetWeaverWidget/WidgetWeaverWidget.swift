//
//  WidgetWeaverWidget.swift
//  WidgetWeaverWidget
//
//  Created by . . on 12/17/25.
//

import WidgetKit
import SwiftUI
import AppIntents

struct WidgetWeaverEntry: TimelineEntry {
    let date: Date
    let spec: WidgetSpec
}

private enum WidgetWeaverSpecEntityIDs {
    static let appDefault = "default"
}

// MARK: - AppEntity for selecting a saved spec

struct WidgetWeaverSpecEntity: AppEntity, Identifiable {
    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Widget Design")
    }

    static var defaultQuery: WidgetWeaverSpecEntityQuery {
        WidgetWeaverSpecEntityQuery()
    }

    var id: String
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: LocalizedStringResource(stringLiteral: name))
    }
}

struct WidgetWeaverSpecEntityQuery: EntityQuery {
    func entities(for identifiers: [WidgetWeaverSpecEntity.ID]) async throws -> [WidgetWeaverSpecEntity] {
        let specs = WidgetSpecStore.shared.loadAll()
        let byID = Dictionary(uniqueKeysWithValues: specs.map { ($0.id.uuidString, $0) })

        return identifiers.compactMap { id in
            if id == WidgetWeaverSpecEntityIDs.appDefault {
                return WidgetWeaverSpecEntity(id: id, name: "Default (App)")
            }
            guard let spec = byID[id] else { return nil }
            return WidgetWeaverSpecEntity(id: spec.id.uuidString, name: spec.name)
        }
    }

    func suggestedEntities() async throws -> [WidgetWeaverSpecEntity] {
        let defaultEntity = WidgetWeaverSpecEntity(id: WidgetWeaverSpecEntityIDs.appDefault, name: "Default (App)")
        let saved = WidgetSpecStore.shared
            .loadAll()
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { WidgetWeaverSpecEntity(id: $0.id.uuidString, name: $0.name) }

        return [defaultEntity] + saved
    }

    func defaultResult() async -> WidgetWeaverSpecEntity? {
        WidgetWeaverSpecEntity(id: WidgetWeaverSpecEntityIDs.appDefault, name: "Default (App)")
    }
}

// MARK: - Widget configuration intent

struct WidgetWeaverConfigurationIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "WidgetWeaver" }

    static var description: IntentDescription {
        IntentDescription("Choose which saved WidgetWeaver design to render.")
    }

    @Parameter(title: "Design")
    var spec: WidgetWeaverSpecEntity?

    init() { }
}

// MARK: - Provider

struct WidgetWeaverProvider: AppIntentTimelineProvider {
    typealias Intent = WidgetWeaverConfigurationIntent
    typealias Entry = WidgetWeaverEntry

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), spec: .defaultSpec())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let spec = loadSpec(for: configuration)
        return Entry(date: Date(), spec: spec)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let spec = loadSpec(for: configuration)
        let entry = Entry(date: Date(), spec: spec)
        return Timeline(entries: [entry], policy: .never)
    }

    private func loadSpec(for configuration: Intent) -> WidgetSpec {
        let store = WidgetSpecStore.shared

        guard
            let idString = configuration.spec?.id,
            idString != WidgetWeaverSpecEntityIDs.appDefault,
            let id = UUID(uuidString: idString),
            let spec = store.load(id: id)
        else {
            return store.loadDefault()
        }

        return spec.normalised()
    }
}

// MARK: - Widget view

struct WidgetWeaverWidgetView: View {
    let entry: WidgetWeaverEntry

    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetWeaverSpecView(spec: entry.spec, family: family, context: .widget)
    }
}

// MARK: - Widget

struct WidgetWeaverWidget: Widget {
    let kind: String = WidgetWeaverWidgetKinds.main

    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: kind,
            intent: WidgetWeaverConfigurationIntent.self,
            provider: WidgetWeaverProvider()
        ) { entry in
            WidgetWeaverWidgetView(entry: entry)
        }
        .configurationDisplayName("WidgetWeaver")
        .description("Renders a selected saved WidgetWeaver spec.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

#Preview(as: .systemSmall) {
    WidgetWeaverWidget()
} timeline: {
    WidgetWeaverEntry(date: .now, spec: .defaultSpec())
}
