//
//  WidgetWeaverAboutCatalog.swift
//  WidgetWeaver
//
//  Created by . . on 12/20/25.
//

import Foundation

extension WidgetWeaverAboutView {
    static let featuredWeatherTemplateID: String = "starter-weather"
    static let featuredCalendarTemplateID: String = "starter-calendar-nextup"

    static var featuredWeatherTemplate: WidgetWeaverAboutTemplate {
        starterTemplates.first(where: { $0.id == featuredWeatherTemplateID })
        ?? WidgetWeaverAboutTemplate(
            id: featuredWeatherTemplateID,
            title: "Weather",
            subtitle: "Rain-first nowcast",
            description: "A rain-first layout with glass panels and adaptive small/medium/large composition.",
            tags: ["Weather", "Rain chart", "Dynamic", "Glass"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specWeather()
        )
    }

    static var featuredCalendarTemplate: WidgetWeaverAboutTemplate {
        starterTemplates.first(where: { $0.id == featuredCalendarTemplateID })
        ?? WidgetWeaverAboutTemplate(
            id: featuredCalendarTemplateID,
            title: "Calendar",
            subtitle: "Next Up",
            description: "Upcoming events from your calendars. Requires Calendar access.",
            tags: ["Calendar", "Next up", "Events"],
            requiresPro: false,
            triggersCalendarPermission: true,
            spec: specNextUpCalendar()
        )
    }

    static var promptIdeas: [String] {
        [
            "minimal focus widget, teal accent, no symbol, short text",
            "bold countdown widget, centred layout, purple accent, bigger title",
            "quote card, subtle material background, grey accent, no secondary text",
            "shopping list reminder, green accent, checklist icon",
            "reading progress widget, blue accent, book icon, short secondary text",
            "workout routine widget, red accent, strong title, simple layout",
            "note widget, horizontal layout, orange accent, minimal styling",
            "habit streak widget, orange accent, uses {{streak|0}} and {{last_done|Never|relative}}, with interactive buttons",
            "weather widget, glass look, strong accent, rain-first"
        ]
    }

    static var patchIdeas: [String] {
        [
            "more minimal",
            "bigger title",
            "change accent to teal",
            "switch to horizontal layout",
            "centre the layout",
            "remove the symbol",
            "remove secondary text",
            "add interactive buttons"
        ]
    }

    static var starterTemplates: [WidgetWeaverAboutTemplate] {
        [
            WidgetWeaverAboutTemplate(
                id: "starter-focus",
                title: "Focus",
                subtitle: "Minimal daily focus card",
                description: "A clean, glanceable widget for a single priority.",
                tags: ["Text"],
                requiresPro: false,
                triggersCalendarPermission: false,
                spec: specFocus()
            ),
            WidgetWeaverAboutTemplate(
                id: "starter-countdown",
                title: "Countdown",
                subtitle: "Bold countdown styling",
                description: "A simple countdown layout with a larger primary line.",
                tags: ["Text"],
                requiresPro: false,
                triggersCalendarPermission: false,
                spec: specCountdown()
            ),
            WidgetWeaverAboutTemplate(
                id: "starter-quote",
                title: "Quote",
                subtitle: "Quote / affirmation card",
                description: "Good for short quotes, affirmations, or reminders.",
                tags: ["Text"],
                requiresPro: false,
                triggersCalendarPermission: false,
                spec: specQuote()
            ),
            WidgetWeaverAboutTemplate(
                id: "starter-list",
                title: "List",
                subtitle: "Shopping / checklist style",
                description: "A compact list-style widget using a single text line.",
                tags: ["Text"],
                requiresPro: false,
                triggersCalendarPermission: false,
                spec: specList()
            ),
            WidgetWeaverAboutTemplate(
                id: "starter-reading",
                title: "Reading",
                subtitle: "Progress cue",
                description: "A reading prompt with a clear next-step.",
                tags: ["Text"],
                requiresPro: false,
                triggersCalendarPermission: false,
                spec: specReading()
            ),
            WidgetWeaverAboutTemplate(
                id: featuredWeatherTemplateID,
                title: "Weather",
                subtitle: "Rain-first nowcast",
                description: "Weather template with cached snapshot rendering in widgets.",
                tags: ["Weather"],
                requiresPro: false,
                triggersCalendarPermission: false,
                spec: specWeather()
            ),
            WidgetWeaverAboutTemplate(
                id: featuredCalendarTemplateID,
                title: "Calendar",
                subtitle: "Next Up",
                description: "Upcoming events from your calendars. Requires Calendar access.",
                tags: ["Calendar"],
                requiresPro: false,
                triggersCalendarPermission: true,
                spec: specNextUpCalendar()
            )
        ]
    }

    static var proTemplates: [WidgetWeaverAboutTemplate] {
        [
            WidgetWeaverAboutTemplate(
                id: "pro-habit-streak",
                title: "Habit Streak",
                subtitle: "Variables + buttons (Pro)",
                description: "A variable-driven streak template (pairs well with interactive buttons).",
                tags: ["Variables", "Buttons"],
                requiresPro: true,
                triggersCalendarPermission: false,
                spec: specHabitStreak()
            ),
            WidgetWeaverAboutTemplate(
                id: "pro-counter",
                title: "Counter",
                subtitle: "Tap to update (Pro)",
                description: "A simple counter template (pairs well with +1 / -1 buttons).",
                tags: ["Variables", "Buttons"],
                requiresPro: true,
                triggersCalendarPermission: false,
                spec: specCounter()
            )
        ]
    }

    // MARK: - Spec builders (simple, safe defaults)

    static func specFocus() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Focus"
        spec.primaryText = "Today’s focus"
        spec.secondaryText = "One thing that matters."
        spec.layout.template = .classic
        return spec.normalised()
    }

    static func specCountdown() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Countdown"
        spec.primaryText = "10 days"
        spec.secondaryText = "Until the thing."
        spec.layout.template = .hero
        return spec.normalised()
    }

    static func specQuote() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Quote"
        spec.primaryText = "“Do the work.”"
        spec.secondaryText = "Small steps, daily."
        spec.layout.template = .classic
        return spec.normalised()
    }

    static func specList() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "List"
        spec.primaryText = "• Milk  • Eggs  • Coffee"
        spec.secondaryText = "Tap to edit in the app."
        spec.layout.template = .classic
        return spec.normalised()
    }

    static func specReading() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Reading"
        spec.primaryText = "Next: Chapter 7"
        spec.secondaryText = "Progress: {{progress|0|bar:10}}"
        spec.layout.template = .classic
        return spec.normalised()
    }

    static func specWeather() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Weather"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .weather
        return spec.normalised()
    }

    static func specNextUpCalendar() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Next Up"
        spec.primaryText = ""
        spec.secondaryText = nil
        spec.layout.template = .nextUpCalendar
        return spec.normalised()
    }

    static func specHabitStreak() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Habit Streak"
        spec.primaryText = "Streak: {{streak|0}} days"
        spec.secondaryText = "Last: {{last_done|Never|relative}}"
        spec.layout.template = .hero
        return spec.normalised()
    }

    static func specCounter() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Counter"
        spec.primaryText = "{{count|0}}"
        spec.secondaryText = "Tap buttons to update"
        spec.layout.template = .hero
        return spec.normalised()
    }
}
