//
//  WidgetWeaverDeepLinkHost.swift
//  WidgetWeaver
//
//  Created by . . on 01/02/26.
//

import Foundation
import SwiftUI

enum WidgetWeaverDeepLink: String, Identifiable {
    case noiseMachine
    case pawPulseLatestCat
    case pawPulseSettings
    case clock
    case remindersAccess

    var id: String { rawValue }

    static func from(url: URL) -> WidgetWeaverDeepLink? {
        guard let scheme = url.scheme?.lowercased(), scheme == "widgetweaver" else { return nil }

        // Support either host or first path segment.
        let host = (url.host ?? "").lowercased()
        let pathSegments = url.pathComponents.dropFirst().map { $0.lowercased() }
        let first = pathSegments.first ?? ""
        let second = pathSegments.dropFirst().first ?? ""

        if host == "noisemachine" || host == "noise-machine" {
            return .noiseMachine
        }

        if host == "pawpulse" || host == "paw-pulse" {
            if first == "settings" {
                return .pawPulseSettings
            }
            return .pawPulseLatestCat
        }

        if host == "clock" {
            return .clock
        }

        // Reminders: widgetweaver://reminders/access
        if host == "reminders" || host == "reminders-access" || host == "reminders-permissions" || host == "reminderssettings" {
            if first.isEmpty || first == "access" || first == "permissions" || first == "request" || first == "request-access" || first == "settings" {
                return .remindersAccess
            }
            return .remindersAccess
        }

        // Path-based variants: widgetweaver://open/clock etc.
        if first == "clock" {
            return .clock
        }

        if first == "reminders" {
            // widgetweaver://open/reminders/access
            if second.isEmpty || second == "access" || second == "permissions" || second == "request" || second == "request-access" || second == "settings" {
                return .remindersAccess
            }
            return .remindersAccess
        }

        if first == "reminders-access" || first == "reminders-permissions" || first == "reminderssettings" {
            return .remindersAccess
        }

        return nil
    }
}

struct WidgetWeaverDeepLinkHost<Content: View>: View {
    @State private var activeDeepLink: WidgetWeaverDeepLink?

    let content: () -> Content

    var body: some View {
        content()
            .onOpenURL { url in
                if let deepLink = WidgetWeaverDeepLink.from(url: url) {
                    activeDeepLink = deepLink
                }
            }
            .sheet(item: $activeDeepLink) { deepLink in
                switch deepLink {
                case .remindersAccess:
                    WidgetWeaverRemindersSettingsView(onClose: { activeDeepLink = nil })

                case .noiseMachine, .pawPulseLatestCat, .pawPulseSettings, .clock:
                    NavigationStack {
                        deepLinkDestination(deepLink)
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .topBarLeading) {
                                    Button("Close") { activeDeepLink = nil }
                                }
                            }
                    }
                }
            }
    }

    @ViewBuilder
    private func deepLinkDestination(_ deepLink: WidgetWeaverDeepLink) -> some View {
        switch deepLink {
        case .noiseMachine:
            NoiseMachineView()

        case .pawPulseLatestCat:
            PawPulseLatestCatDetailView()

        case .pawPulseSettings:
            PawPulseSettingsView()

        case .clock:
            WidgetWeaverClockDeepLinkView()

        case .remindersAccess:
            WidgetWeaverRemindersSettingsView(onClose: { activeDeepLink = nil })
        }
    }
}

private enum WidgetWeaverClockDesignerTheme: String, CaseIterable, Identifiable {
    case classic
    case ocean
    case graphite

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .classic:
            return "Classic"
        case .ocean:
            return "Ocean"
        case .graphite:
            return "Graphite"
        }
    }

    var accent: AccentToken {
        switch self {
        case .classic:
            return .orange
        case .ocean:
            return .blue
        case .graphite:
            return .gray
        }
    }
}

private enum WWClockDesignerCreateSource: String {
    case manual
    case upgradeFromQuick
}

private struct WWClockQuickConfigurationSnapshot {
    let lastTimelineBuildAt: Date
    let scheme: WidgetWeaverClockColourScheme
    let secondsHandEnabled: Bool
}

private extension WidgetWeaverClockColourScheme {
    var displayName: String {
        switch self {
        case .classic: return "Classic"
        case .ocean: return "Ocean"
        case .mint: return "Mint"
        case .orchid: return "Orchid"
        case .sunset: return "Sunset"
        case .ember: return "Ember"
        case .graphite: return "Graphite"
        }
    }

    var mappedDesignerTheme: WidgetWeaverClockDesignerTheme {
        switch self {
        case .ocean:
            return .ocean
        case .graphite:
            return .graphite
        default:
            return .classic
        }
    }

    var requiresThemeNote: Bool {
        switch self {
        case .classic, .ocean, .graphite:
            return false
        default:
            return true
        }
    }
}

private enum WWClockQuickConfigurationReader {
    private static let lastKey = "widgetweaver.clock.timelineBuild.last"
    private static let schemeKey = "widgetweaver.clock.timelineBuild.scheme"
    private static let secondsKey = "widgetweaver.clock.timelineBuild.secondsHandEnabled"

    static func load() -> WWClockQuickConfigurationSnapshot? {
        let defaults = AppGroup.userDefaults

        guard let last = defaults.object(forKey: lastKey) as? Date else { return nil }
        guard let schemeRaw = defaults.object(forKey: schemeKey) as? Int else { return nil }
        guard let scheme = WidgetWeaverClockColourScheme(rawValue: schemeRaw) else { return nil }

        let seconds = defaults.object(forKey: secondsKey) as? Bool ?? false

        return WWClockQuickConfigurationSnapshot(
            lastTimelineBuildAt: last,
            scheme: scheme,
            secondsHandEnabled: seconds
        )
    }
}

private enum WWClockDesignerFunnelMetrics {
    private static let openedCountKey = "widgetweaver.clockDesigner.funnel.opened.count"
    private static let openedLastKey = "widgetweaver.clockDesigner.funnel.opened.last"

    private static let createTappedCountKey = "widgetweaver.clockDesigner.create.tapped.count"
    private static let createSucceededCountKey = "widgetweaver.clockDesigner.create.succeeded.count"

    private static let createLastKey = "widgetweaver.clockDesigner.create.last"
    private static let createLastSourceKey = "widgetweaver.clockDesigner.create.last.source"
    private static let createLastThemeKey = "widgetweaver.clockDesigner.create.last.theme"
    private static let createLastDesignIDKey = "widgetweaver.clockDesigner.create.last.designID"

    static func recordOpened(now: Date = Date()) {
        let defaults = AppGroup.userDefaults
        defaults.set(now, forKey: openedLastKey)
        defaults.set(defaults.integer(forKey: openedCountKey) + 1, forKey: openedCountKey)
    }

    static func recordCreateTapped(source: WWClockDesignerCreateSource, theme: WidgetWeaverClockDesignerTheme, now: Date = Date()) {
        let defaults = AppGroup.userDefaults
        defaults.set(now, forKey: createLastKey)
        defaults.set(source.rawValue, forKey: createLastSourceKey)
        defaults.set(theme.rawValue, forKey: createLastThemeKey)
        defaults.set(defaults.integer(forKey: createTappedCountKey) + 1, forKey: createTappedCountKey)
    }

    static func recordCreateSucceeded(source: WWClockDesignerCreateSource, theme: WidgetWeaverClockDesignerTheme, designID: UUID, now: Date = Date()) {
        let defaults = AppGroup.userDefaults
        defaults.set(now, forKey: createLastKey)
        defaults.set(source.rawValue, forKey: createLastSourceKey)
        defaults.set(theme.rawValue, forKey: createLastThemeKey)
        defaults.set(designID.uuidString, forKey: createLastDesignIDKey)
        defaults.set(defaults.integer(forKey: createSucceededCountKey) + 1, forKey: createSucceededCountKey)
    }
}

private struct WidgetWeaverClockDeepLinkView: View {
    @State private var theme: WidgetWeaverClockDesignerTheme = .classic
    @State private var quickSnapshot: WWClockQuickConfigurationSnapshot?
    @State private var statusMessage: String = ""

    var body: some View {
        List {
            Section {
                Text("Clock (Quick) is a dedicated Home Screen (Small) widget for a fast add with minimal configuration.")
                    .foregroundStyle(.secondary)

                Text("Clock (Designer) is a Design template inside WidgetWeaver, intended for deep customisation and consistent styling.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Two ways to place Clock")
            }

            if let quickSnapshot {
                Section {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Detected last Clock (Quick) settings:")
                            .foregroundStyle(.secondary)

                        Text("Colour scheme: \(quickSnapshot.scheme.displayName)")

                        Text("Seconds hand: \(quickSnapshot.secondsHandEnabled ? "On" : "Off")")

                        Text("Last updated: \(quickSnapshot.lastTimelineBuildAt.formatted(date: .abbreviated, time: .shortened))")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if quickSnapshot.scheme.requiresThemeNote {
                            Text("Designer clocks currently support Classic, Ocean, and Graphite. \"\(quickSnapshot.scheme.displayName)\" maps to Classic as the closest match.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Button {
                            createDesignerClock(
                                theme: quickSnapshot.scheme.mappedDesignerTheme,
                                nameQualifier: quickSnapshot.scheme.displayName,
                                source: .upgradeFromQuick
                            )
                        } label: {
                            Label("Upgrade to Clock (Designer)", systemImage: "arrow.up.right.circle.fill")
                        }
                    }
                } header: {
                    Text("Upgrade from Clock (Quick)")
                } footer: {
                    Text("The new design is saved into the Library. Add a WidgetWeaver widget, then choose the design in Edit Widget → Design.")
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(WidgetWeaverClockDesignerTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }

                Button {
                    createDesignerClock(theme: theme, nameQualifier: nil, source: .manual)
                } label: {
                    Label("Create Clock (Designer) design", systemImage: "plus.circle.fill")
                }
            } header: {
                Text("Create a Designer Clock")
            } footer: {
                Text("The new design is saved into the Library. Add a WidgetWeaver widget, then choose the design in Edit Widget → Design.")
                    .foregroundStyle(.secondary)
            }

            if !statusMessage.isEmpty {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Clock")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            WWClockDesignerFunnelMetrics.recordOpened()

            let snap = WWClockQuickConfigurationReader.load()
            quickSnapshot = snap

            if let snap {
                theme = snap.scheme.mappedDesignerTheme
            }
        }
    }

    private func createDesignerClock(
        theme: WidgetWeaverClockDesignerTheme,
        nameQualifier: String?,
        source: WWClockDesignerCreateSource
    ) {
        WWClockDesignerFunnelMetrics.recordCreateTapped(source: source, theme: theme)

        let qualifier = (nameQualifier ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        let baseName: String = {
            if qualifier.isEmpty {
                return "Clock (Designer — \(theme.displayName))"
            }
            return "Clock (Designer — \(theme.displayName), \(qualifier))"
        }()

        let name = makeUniqueDesignName(base: baseName)

        var spec = WidgetSpec.defaultSpec()

        spec.name = name
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.symbol = nil
        spec.image = nil

        spec.layout.template = .clockIcon
        spec.layout.showsAccentBar = false

        spec.style.accent = theme.accent

        spec.clockConfig = WidgetWeaverClockDesignConfig(theme: theme.rawValue)

        WidgetSpecStore.shared.save(spec.normalised(), makeDefault: false)

        WidgetWeaverClockDesignerMetrics.recordCreatedDesignID(spec.id)

        WWClockDesignerFunnelMetrics.recordCreateSucceeded(source: source, theme: theme, designID: spec.id)

        statusMessage = "Created \(name). Find it in Library to edit, then apply it to a WidgetWeaver widget."
    }

    private func makeUniqueDesignName(base: String) -> String {
        let existing = Set(WidgetSpecStore.shared.loadAll().map(\.name))
        if !existing.contains(base) { return base }

        let suffix = UUID().uuidString.prefix(8)
        return "\(base) \(suffix)"
    }
}
