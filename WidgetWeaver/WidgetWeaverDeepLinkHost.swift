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

private struct WidgetWeaverClockDeepLinkView: View {
    @State private var theme: WidgetWeaverClockDesignerTheme = .classic
    @State private var statusMessage: String = ""

    var body: some View {
        List {
            Section {
                Text("Clock (Quick) is a dedicated Home Screen widget for a fast add with minimal configuration.")
                    .foregroundStyle(.secondary)

                Text("Clock (Designer) is a Design template inside WidgetWeaver, intended for deep customisation and consistent styling.")
                    .foregroundStyle(.secondary)
            } header: {
                Text("Two ways to place Clock")
            }

            Section {
                Picker("Theme", selection: $theme) {
                    ForEach(WidgetWeaverClockDesignerTheme.allCases) { theme in
                        Text(theme.displayName).tag(theme)
                    }
                }

                Button {
                    createDesignerClock(theme: theme)
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
    }

    private func createDesignerClock(theme: WidgetWeaverClockDesignerTheme) {
        let baseName = "Clock (Designer — \(theme.displayName))"
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

        statusMessage = "Created \(name). Find it in Library to edit, then apply it to a WidgetWeaver widget."
    }

    private func makeUniqueDesignName(base: String) -> String {
        let existing = Set(WidgetSpecStore.shared.loadAll().map(\.name))
        if !existing.contains(base) { return base }

        let suffix = UUID().uuidString.prefix(8)
        return "\(base) \(suffix)"
    }
}
