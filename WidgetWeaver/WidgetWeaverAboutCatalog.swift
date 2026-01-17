//
//  WidgetWeaverAboutCatalog.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation
import SwiftUI
import WidgetKit

extension WidgetWeaverAboutView {
    static let featuredWeatherTemplateID = "starter-weather"
    static let featuredCalendarTemplateID = "starter-calendar-nextup"
    static let featuredStepsTemplateID = "starter-steps"

    static let featuredWeatherTemplate: WidgetWeaverAboutTemplate = starterTemplatesAll.first(where: { $0.id == featuredWeatherTemplateID })!
    static let featuredCalendarTemplate: WidgetWeaverAboutTemplate = starterTemplatesAll.first(where: { $0.id == featuredCalendarTemplateID })!
    static let featuredStepsTemplate: WidgetWeaverAboutTemplate = starterTemplatesAll.first(where: { $0.id == featuredStepsTemplateID })!

    static let featuredTemplateIDs: Set<String> = [
        featuredWeatherTemplateID,
        featuredCalendarTemplateID,
        featuredStepsTemplateID,
    ]

    private static func deduplicatedTemplates(_ templates: [WidgetWeaverAboutTemplate]) -> [WidgetWeaverAboutTemplate] {
        var seen = Set<String>()
        return templates.filter { template in
            seen.insert(template.id).inserted
        }
    }

    static let starterTemplatesAll: [WidgetWeaverAboutTemplate] = [
        WidgetWeaverAboutTemplate(
            id: "starter-focus",
            title: "Focus",
            subtitle: "Daily priority",
            description: "A calm “one thing” widget with a warm gradient and a soft accent glow.",
            tags: ["Daily", "Focus", "Glow"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specFocus()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-countdown",
            title: "Countdown",
            subtitle: "Timebox / deadline",
            description: "A bold hero-style countdown with a colourful background and strong accent bar.",
            tags: ["Timer", "Countdown", "Hero"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specCountdown()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-quote",
            title: "Quote",
            subtitle: "Motivation",
            description: "A simple quote layout with a sunset gradient and a clean typography stack.",
            tags: ["Quote", "Motivation", "Gradient"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specQuote()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-list",
            title: "List",
            subtitle: "Checklist",
            description: "A checklist-style widget with a vibrant background and a green accent bar.",
            tags: ["Checklist", "Lists", "Clean"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specList()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-today",
            title: "Today",
            subtitle: "Reminders",
            description: "Reminders due today.",
            tags: ["Reminders", "Today"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersToday()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-overdue",
            title: "Overdue",
            subtitle: "Reminders",
            description: "Overdue reminders, sorted by due date.",
            tags: ["Reminders", "Overdue"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersOverdue()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-soon",
            title: "Soon",
            subtitle: "Reminders",
            description: "Upcoming reminders in the next few hours.",
            tags: ["Reminders", "Soon"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersSoon()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-priority",
            title: "Priority",
            subtitle: "Reminders",
            description: "High-priority reminders (flagged approximation).",
            tags: ["Reminders", "Priority"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersPriority()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-focus",
            title: "Focus",
            subtitle: "Reminders",
            description: "A calm one-thing view for a single reminder.",
            tags: ["Reminders", "Focus"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersFocus()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-list",
            title: "Lists",
            subtitle: "Reminders",
            description: "All reminders sorted by list.",
            tags: ["Reminders", "Lists"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersLists()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reading",
            title: "Reading",
            subtitle: "Progress",
            description: "Track a small goal (pages, minutes, chapters) with a calm indigo glow.",
            tags: ["Reading", "Progress", "Calm"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specReading()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-steps",
            title: "Steps",
            subtitle: "Today + goal progress",
            description: "A simple Steps widget powered by built-in __steps_* keys.\nEnable Health access in the app first.",
            tags: ["Steps", "Health", "Goal"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specSteps()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-activity",
            title: "Activity",
            subtitle: "Steps + more (Health)",
            description: "A multi-metric Activity widget powered by built-in __activity_* keys.\nEnable Activity access in the app first.",
            tags: ["Activity", "Health", "Snapshot"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specActivity()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-weather",
            title: "Weather",
            subtitle: "Rain-first nowcast",
            description: "Rain-first Weather template with a blue accent, glass panels, and an hourly strip.",
            tags: ["Rain", "Nowcast", "Hourly"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specWeather()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-calendar-nextup",
            title: "Next Up",
            subtitle: "Calendar events",
            description: "Upcoming events from Apple Calendar (on-device).\nRequires Calendar permission.",
            tags: ["Next Up", "Events", "On-device"],
            requiresPro: false,
            triggersCalendarPermission: true,
            spec: specNextUpCalendar()
        ),
    ]

    /// Templates shown in the Templates section on Explore.
    ///
    /// Featured templates already appear above as large cards, so they’re excluded here to avoid duplicates.
    static let starterTemplates: [WidgetWeaverAboutTemplate] = deduplicatedTemplates(
        starterTemplatesAll.filter { !featuredTemplateIDs.contains($0.id) }
    )

    static let proTemplates: [WidgetWeaverAboutTemplate] = [
        WidgetWeaverAboutTemplate(
            id: "pro-habit-streak",
            title: "Habit Streak",
            subtitle: "Buttons + variables",
            description: "A streak counter powered by variables, with a “Done” button and a +1 button.",
            tags: ["Streak", "Buttons", "Variables"],
            requiresPro: true,
            triggersCalendarPermission: false,
            spec: specHabitStreak()
        ),
        WidgetWeaverAboutTemplate(
            id: "pro-counter",
            title: "Counter",
            subtitle: "+1 / -1 buttons",
            description: "A colourful counter with two interactive buttons to update a shared variable.",
            tags: ["Counter", "Buttons", "Variables"],
            requiresPro: true,
            triggersCalendarPermission: false,
            spec: specCounter()
        ),
    ]

    static let promptIdeas: [String] = [
        "Make a daily focus widget with a teal accent, a soft glow, and one clear sentence.",
        "Create a quote widget with a warm gradient background and a subtle icon.",
        "Design a checklist widget with an accent bar and a tidy stacked layout.",
        "Build a countdown widget in a bold hero style with an accent glow.",
        "Make a reading progress widget that feels calm and minimal, using indigo.",
    ]

    static let patchIdeas: [String] = [
        "Change the accent colour to teal and enable the background glow.",
        "Switch thech the background to Sunset and increase corner radius slightly.",
        "Turn on the accent bar and shorten the secondary text.",
        "Use Hero template and increase primary font size one step.",
        "Make the design more vibrant: add a background overlay at ~10% opacity.",
    ]

    // MARK: - Template specs (colourful defaults)

    static func specFocus() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Focus"
        spec.primaryText = "Today’s focus"
        spec.secondaryText = "One thing that matters."
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .teal
        spec.style.background = .radialGlow
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.12
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "scope",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        return spec.normalised()
    }

    static func specCountdown() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Countdown"
        spec.primaryText = "7 days"
        spec.secondaryText = "Until the big day."
        spec.layout.template = .hero
        spec.layout.showsAccentBar = true
        spec.style.accent = .purple
        spec.style.background = .accentGlow
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.10
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "timer",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        return spec.normalised()
    }

    static func specQuote() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Quote"
        spec.primaryText = "Make it simple."
        spec.secondaryText = "Do the next right thing."
        spec.layout.template = .classic
        spec.layout.showsAccentBar = false
        spec.style.accent = .pink
        spec.style.background = .sunset
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = false
        spec.symbol = SymbolSpec(
            name: "quote.opening",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        return spec.normalised()
    }

    static func specList() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "List"
        spec.primaryText = "Shopping"
        spec.secondaryText = "• Milk\n• Eggs\n• Coffee"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .green
        spec.style.background = .sunset
        spec.style.backgroundOverlay = .radialGlow
        spec.style.backgroundOverlayOpacity = 0.22
        spec.style.backgroundGlowEnabled = false
        spec.symbol = SymbolSpec(
            name: "checklist",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        return spec.normalised()
    }

    static func specReading() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Reading"
        spec.primaryText = "12 / 30 pages"
        spec.secondaryText = "Tonight: 20 mins"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = false
        spec.style.accent = .indigo
        spec.style.background = .radialGlow
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.08
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "book.closed",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        return spec.normalised()
    }

    static func specSteps() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Steps"
        spec.primaryText = "{{__steps_today|--|number:0}}"
        spec.secondaryText = "Goal {{__steps_goal_today|--|number:0}} • {{__steps_today_fraction|0|percent:0}}"
        spec.layout.template = .hero
        spec.layout.showsAccentBar = true
        spec.style.accent = .green
        spec.style.background = .radialGlow
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "figure.walk",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        return spec.normalised()
    }

    static func specActivity() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Activity"
        spec.primaryText = "{{__activity_steps_today|--|number:0}}"
        spec.secondaryText = "{{__activity_distance_km|--}} • {{__activity_flights_today|--|number:0}} flights\n{{__activity_active_energy_kcal|--|number:0}} kcal"
        spec.layout.template = .hero
        spec.layout.showsAccentBar = true
        spec.layout.secondaryLineLimitSmall = 2
        spec.layout.secondaryLineLimit = 2
        spec.style.accent = .orange
        spec.style.background = .radialGlow
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "figure.walk.circle",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        return spec.normalised()
    }

    static func specWeather() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Weather"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .weather
        spec.layout.showsAccentBar = false
        spec.style.accent = .blue
        spec.style.background = .plain
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = false
        spec.style.weatherScale = 1.0
        spec.symbol = nil
        return spec.normalised()
    }

    static func specNextUpCalendar() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Next Up"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .nextUpCalendar
        spec.layout.showsAccentBar = false
        spec.style.accent = .green
        spec.style.background = .plain
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = false
        spec.symbol = nil
        return spec.normalised()
    }

    static func specRemindersToday() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Reminders 1 — Today"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .reminders
        spec.layout.showsAccentBar = true
        spec.style.accent = .blue
        spec.style.background = .plain
        spec.style.backgroundOverlay = .radialGlow
        spec.style.backgroundOverlayOpacity = 0.16
        spec.style.backgroundGlowEnabled = false
        spec.symbol = nil
        spec.remindersConfig = WidgetWeaverRemindersConfig(mode: .today, presentation: .dense)
        return spec.normalised()
    }

    static func specRemindersOverdue() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Reminders 2 — Overdue"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .reminders
        spec.layout.showsAccentBar = true
        spec.style.accent = .red
        spec.style.background = .plain
        spec.style.backgroundOverlay = .radialGlow
        spec.style.backgroundOverlayOpacity = 0.14
        spec.style.backgroundGlowEnabled = false
        spec.symbol = nil
        spec.remindersConfig = WidgetWeaverRemindersConfig(mode: .overdue, presentation: .dense)
        return spec.normalised()
    }

    static func specRemindersSoon() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Reminders 3 — Soon"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .reminders
        spec.layout.showsAccentBar = true
        spec.style.accent = .orange
        spec.style.background = .plain
        spec.style.backgroundOverlay = .radialGlow
        spec.style.backgroundOverlayOpacity = 0.14
        spec.style.backgroundGlowEnabled = false
        spec.symbol = nil
        spec.remindersConfig = WidgetWeaverRemindersConfig(mode: .soon, presentation: .dense, soonWindowMinutes: 360)
        return spec.normalised()
    }

    static func specRemindersPriority() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Reminders 4 — Priority"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .reminders
        spec.layout.showsAccentBar = true
        spec.style.accent = .yellow
        spec.style.background = .plain
        spec.style.backgroundOverlay = .radialGlow
        spec.style.backgroundOverlayOpacity = 0.12
        spec.style.backgroundGlowEnabled = false
        spec.symbol = nil
        spec.remindersConfig = WidgetWeaverRemindersConfig(mode: .flagged, presentation: .dense)
        return spec.normalised()
    }

    static func specRemindersFocus() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Reminders 5 — Focus"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .reminders
        spec.layout.showsAccentBar = false
        spec.style.accent = .purple
        spec.style.background = .radialGlow
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = true
        spec.symbol = nil
        spec.remindersConfig = WidgetWeaverRemindersConfig(mode: .focus, presentation: .focus)
        return spec.normalised()
    }

    static func specRemindersLists() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Reminders 6 — Lists"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .reminders
        spec.layout.showsAccentBar = true
        spec.style.accent = .green
        spec.style.background = .plain
        spec.style.backgroundOverlay = .radialGlow
        spec.style.backgroundOverlayOpacity = 0.14
        spec.style.backgroundGlowEnabled = false
        spec.symbol = nil
        spec.remindersConfig = WidgetWeaverRemindersConfig(mode: .list, presentation: .dense)
        return spec.normalised()
    }

    static func specHabitStreak() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Habit Streak"
        spec.primaryText = "Streak: {{streak|0}} days"
        spec.secondaryText = "Last: {{last_done|Never|relative}}"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .orange
        spec.style.background = .radialGlow
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.10
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "flame.fill",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        spec.actionBar = WidgetActionBarSpec(
            actions: [
                WidgetActionSpec(
                    title: "Done",
                    systemImage: "checkmark.circle.fill",
                    kind: .setVariableToNow,
                    variableKey: "last_done",
                    incrementAmount: 1,
                    nowFormat: .iso8601
                ),
                WidgetActionSpec(
                    title: "+1",
                    systemImage: "plus.circle.fill",
                    kind: .incrementVariable,
                    variableKey: "streak",
                    incrementAmount: 1,
                    nowFormat: .iso8601
                ),
            ],
            style: .prominent
        )
        return spec.normalised()
    }

    static func specCounter() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Counter"
        spec.primaryText = "Count: {{count|0}}"
        spec.secondaryText = "Tap buttons to update"
        spec.layout.template = .hero
        spec.layout.showsAccentBar = true
        spec.style.accent = .red
        spec.style.background = .accentGlow
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.12
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "plusminus.circle",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        spec.actionBar = WidgetActionBarSpec(
            actions: [
                WidgetActionSpec(
                    title: "+1",
                    systemImage: "plus.circle.fill",
                    kind: .incrementVariable,
                    variableKey: "count",
                    incrementAmount: 1,
                    nowFormat: .iso8601
                ),
                WidgetActionSpec(
                    title: "-1",
                    systemImage: "minus.circle.fill",
                    kind: .incrementVariable,
                    variableKey: "count",
                    incrementAmount: -1,
                    nowFormat: .iso8601
                ),
            ],
            style: .prominent
        )
        return spec.normalised()
    }
}
