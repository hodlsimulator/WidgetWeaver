//
//  WidgetWeaverWidget.swift
//  WidgetWeaverWidget
//
//  Created by Conor on 12/17/25.
//

import WidgetKit
import SwiftUI
import AppIntents

struct WidgetWeaverEntry: TimelineEntry {
    let date: Date
    let spec: WidgetSpec
}

// MARK: - AppEntity for widget configuration

enum WidgetWeaverSpecEntityIDs {
    static let appDefault = "app_default"
}

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
        let store = WidgetSpecStore.shared
        var out: [WidgetWeaverSpecEntity] = []

        for ident in identifiers {
            if ident == WidgetWeaverSpecEntityIDs.appDefault {
                out.append(WidgetWeaverSpecEntity(id: WidgetWeaverSpecEntityIDs.appDefault, name: "Default (App)"))
                continue
            }

            if let uuid = UUID(uuidString: ident),
               let spec = store.load(id: uuid) {
                out.append(WidgetWeaverSpecEntity(id: spec.id.uuidString, name: spec.name))
            }
        }

        return out
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
    static let title: LocalizedStringResource = "WidgetWeaver Design"
    static let description = IntentDescription("Select which saved design this widget should use.")

    @Parameter(title: "Design") var spec: WidgetWeaverSpecEntity?

    static var parameterSummary: some ParameterSummary {
        Summary("Show \(\.$spec)")
    }
}

// MARK: - Timeline provider

struct WidgetWeaverProvider: AppIntentTimelineProvider {
    typealias Entry = WidgetWeaverEntry
    typealias Intent = WidgetWeaverConfigurationIntent

    func placeholder(in context: Context) -> Entry {
        Entry(date: Date(), spec: .defaultSpec())
    }

    func snapshot(for configuration: Intent, in context: Context) async -> Entry {
        let spec = loadSpec(for: configuration)

        if needsWeatherUpdate(for: spec) {
            _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded()
        }

        return Entry(date: Date(), spec: spec)
    }

    func timeline(for configuration: Intent, in context: Context) async -> Timeline<Entry> {
        let spec = loadSpec(for: configuration)

        if needsWeatherUpdate(for: spec) {
            _ = await WidgetWeaverWeatherEngine.shared.updateIfNeeded()
        }

        var refreshSeconds: TimeInterval = 60 * 15

        if needsWeatherUpdate(for: spec) {
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

        if let selected = configuration.spec {
            if selected.id == WidgetWeaverSpecEntityIDs.appDefault {
                return store.loadDefault()
            }
            if let uuid = UUID(uuidString: selected.id),
               let spec = store.load(id: uuid) {
                return spec
            }
        }

        return store.loadDefault()
    }

    private func needsWeatherUpdate(for spec: WidgetSpec) -> Bool {
        // Weather template always needs it.
        if spec.layout.template == .weather { return true }

        // Any design can reference weather variables.
        let primary = spec.primaryText
        let secondary = spec.secondaryText ?? ""

        if primary.localizedCaseInsensitiveContains("__weather_") { return true }
        if secondary.localizedCaseInsensitiveContains("__weather_") { return true }

        return false
    }
}

// MARK: - Widget view

struct WidgetWeaverWidgetView: View {
    let entry: WidgetWeaverProvider.Entry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        WidgetWeaverSpecView(spec: entry.spec, family: family, context: .widget)
    }
}

// MARK: - Widget

struct WidgetWeaverWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(
            kind: WidgetWeaverWidgetKinds.main,
            intent: WidgetWeaverConfigurationIntent.self,
            provider: WidgetWeaverProvider()
        ) { entry in
            WidgetWeaverWidgetView(entry: entry)
        }
        .configurationDisplayName("Design")
        .description("A WidgetWeaver design.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
        .contentMarginsDisabled()
    }
}

#Preview(as: .systemSmall) {
    WidgetWeaverWidget()
} timeline: {
    WidgetWeaverEntry(date: Date(), spec: .defaultSpec())
}
