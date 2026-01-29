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
    static let featuredPhotoTemplateID = "starter-photo-single"
    static let featuredWeatherTemplateID = "starter-weather"
    static let featuredCalendarTemplateID = "starter-calendar-nextup"
    static let featuredStepsTemplateID = "starter-steps"

    static let featuredPhotoTemplate: WidgetWeaverAboutTemplate = starterTemplatesAll.first(where: { $0.id == featuredPhotoTemplateID })!

    static let featuredWeatherTemplate: WidgetWeaverAboutTemplate = starterTemplatesAll.first(where: { $0.id == featuredWeatherTemplateID })!
    static let featuredCalendarTemplate: WidgetWeaverAboutTemplate = starterTemplatesAll.first(where: { $0.id == featuredCalendarTemplateID })!
    static let featuredStepsTemplate: WidgetWeaverAboutTemplate = starterTemplatesAll.first(where: { $0.id == featuredStepsTemplateID })!
 
    static let featuredTemplateIDs: Set<String> = [
        featuredPhotoTemplateID,
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
            id: "starter-photo-single",
            title: "Photo",
            subtitle: "Full-bleed",
            description: "A clean, photo-first widget. Add it, then choose an image in the Editor.",
            tags: ["Photo", "Full-bleed", "Minimal"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specPhotoSingle()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-photo-framed",
            title: "Photo (Framed)",
            subtitle: "Matte frame",
            description: "A framed photo poster with a soft matte border. Add it, then choose an image in the Editor.",
            tags: ["Photo", "Frame", "Matte"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specPhotoFramed()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-photo-caption",
            title: "Photo + Caption",
            subtitle: "Caption overlay",
            description: "A photo poster with a subtle caption panel for readable text over your image.",
            tags: ["Photo", "Caption", "Poster"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specPhotoCaption()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-photo-caption-top",
            title: "Photo + Caption (Top)",
            subtitle: "Top caption",
            description: "A photo poster with a caption panel anchored at the top — useful for portrait photos.",
            tags: ["Photo", "Caption", "Top"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specPhotoCaptionTop()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-photo-caption-glass",
            title: "Photo + Caption (Glass)",
            subtitle: "Glass strip",
            description: "A photo poster with a frosted glass caption strip for readable text over bright photos.",
            tags: ["Photo", "Caption", "Glass"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specPhotoCaptionGlass()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-photo-clock",
            title: "Photo Clock",
            subtitle: "Time overlay",
            description: "A photo poster that shows the current time and weekday over your image.",
            tags: ["Photo", "Clock", "Time"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specPhotoClock()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-photo-quote",
            title: "Photo Quote",
            subtitle: "Motto overlay",
            description: "A photo poster designed for a short quote or motto over a single image.",
            tags: ["Photo", "Quote", "Typography"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specPhotoQuote()
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
            description: "Due today (by local day).",
            tags: ["Reminders", "Today"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersToday()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-overdue",
            title: "Overdue",
            subtitle: "Reminders",
            description: "Due before today (by local day).",
            tags: ["Reminders", "Overdue"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersOverdue()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-soon",
            title: "Upcoming",
            subtitle: "Reminders",
            description: "Due tomorrow through the next 7 days (never includes Today).",
            tags: ["Reminders", "Upcoming"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersSoon()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-priority",
            title: "High priority",
            subtitle: "Reminders",
            description: "Priority 1–4 reminders that are not already in Overdue, Today, or Upcoming.",
            tags: ["Reminders", "High priority"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersPriority()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-focus",
            title: "Anytime",
            subtitle: "Reminders",
            description: "Reminders with no due date (excluding anything already shown above).",
            tags: ["Reminders", "Anytime"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specRemindersFocus()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-reminders-list",
            title: "Lists",
            subtitle: "Reminders",
            description: "The remainder: reminders not already shown in the other pages, grouped by list.",
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
            subtitle: "Today + distance",
            description: "An Activity widget using built-in __activity_* keys.\nEnable Health access in the app first.",
            tags: ["Activity", "Health", "Calories"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specActivity()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-weather",
            title: "Weather",
            subtitle: "Forecast",
            description: "A native Weather widget that reads from the app’s cached forecast.\nEnable Location access in the app first.",
            tags: ["Weather", "Forecast", "Native"],
            requiresPro: false,
            triggersCalendarPermission: false,
            spec: specWeather()
        ),
        WidgetWeaverAboutTemplate(
            id: "starter-calendar-nextup",
            title: "Next Up",
            subtitle: "Calendar",
            description: "A native Calendar widget for upcoming events.\nEnable Calendar access in the app first.",
            tags: ["Calendar", "Upcoming", "Native"],
            requiresPro: false,
            triggersCalendarPermission: true,
            spec: specNextUpCalendar()
        ),
    ]

    /// Templates shown in the Templates section on Explore.
    ///
    /// Featured templates already appear above as large cards, so they’re excluded here to avoid duplicates.
    ///
    /// Some older starter presets remain in the app for back-compat, but are hidden from Explore to keep the
    /// Photos surface curated and reduce duplicate “wrapper” templates.
    private static let exploreHiddenTemplateIDs: Set<String> = [
        "starter-reading",
        "starter-photo-framed",
        "starter-photo-caption",
        "starter-photo-caption-top",
        "starter-photo-caption-glass",
        "starter-photo-clock",
        "starter-photo-quote",
    ]

    static let starterTemplates: [WidgetWeaverAboutTemplate] = deduplicatedTemplates(
        starterTemplatesAll.filter { template in
            if featuredTemplateIDs.contains(template.id) { return false }
            return !exploreHiddenTemplateIDs.contains(template.id)
        }
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
        "Make a calm progress widget that feels minimal, using an indigo accent.",
    ]

    static let patchIdeas: [String] = [
        "Change the accent colour to teal and enable the background glow.",
        "Switch thech the background to Sunset and increase corner radius slightly.",
        "Turn on the accent bar and shorten the secondary text.",
        "Use Hero template and increase primary font size one step.",
        "Make the design more vibrant: add a background overlay at ~10% opacity.",
    ]

    // MARK: - Template specs (colourful defaults)

    static func specPhotoSingle() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Photo"
        spec.primaryText = "Your photo"
        spec.secondaryText = nil
        spec.symbol = nil

        spec.layout.template = .poster
        spec.layout.posterOverlayMode = .none
        spec.layout.showsAccentBar = false

        spec.style.accent = .pink
        spec.style.background = .subtleMaterial
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = false

        return spec.normalised()
    }

    static func specPhotoFramed() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Photo (Framed)"
        spec.primaryText = "Your photo"
        spec.secondaryText = nil
        spec.symbol = nil

        spec.layout.template = .poster
        spec.layout.posterOverlayMode = .none
        spec.layout.showsAccentBar = false

        spec.style.accent = .pink
        spec.style.background = .subtleMaterial
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = false

        return spec.normalised()
    }

    static func specPhotoCaption() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Photo + Caption"
        spec.primaryText = "Your caption"
        spec.secondaryText = "Tap to edit"
        spec.symbol = nil

        spec.layout.template = .poster
        spec.layout.posterOverlayMode = .caption
        spec.layout.showsAccentBar = false

        spec.layout.primaryLineLimitSmall = 1
        spec.layout.primaryLineLimit = 2
        spec.layout.secondaryLineLimitSmall = 1
        spec.layout.secondaryLineLimit = 1

        spec.style.accent = .pink
        spec.style.background = .subtleMaterial
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = false

        spec.style.nameTextStyle = .caption2
        spec.style.primaryTextStyle = .title3
        spec.style.secondaryTextStyle = .caption

        return spec.normalised()
    }

    static func specPhotoCaptionTop() -> WidgetSpec {
        var spec = specPhotoCaption()
        spec.name = "Photo + Caption (Top)"
        spec.layout.alignment = .topLeading
        return spec.normalised()
    }

    static func specPhotoCaptionGlass() -> WidgetSpec {
        var spec = specPhotoCaption()
        spec.name = "Photo + Caption (Glass)"
        spec.style.backgroundOverlay = .subtleMaterial
        spec.style.backgroundOverlayOpacity = 0
        return spec.normalised()
    }

    static func specPhotoClock() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Photo Clock"
        spec.primaryText = "{{__time}}"
        spec.secondaryText = "{{__weekday}}"
        spec.symbol = nil

        spec.layout.template = .poster
        spec.layout.posterOverlayMode = .caption
        spec.layout.showsAccentBar = false

        spec.layout.primaryLineLimitSmall = 1
        spec.layout.primaryLineLimit = 1
        spec.layout.secondaryLineLimitSmall = 1
        spec.layout.secondaryLineLimit = 1

        spec.style.accent = .blue
        spec.style.background = .subtleMaterial
        spec.style.backgroundOverlay = .plain
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = false

        spec.style.nameTextStyle = .caption2
        spec.style.primaryTextStyle = .title
        spec.style.secondaryTextStyle = .caption

        return spec.normalised()
    }

    static func specPhotoQuote() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Photo Quote"
        spec.primaryText = "Stay curious."
        spec.secondaryText = "Tap to edit"
        spec.symbol = nil

        spec.layout.template = .poster
        spec.layout.posterOverlayMode = .caption
        spec.layout.showsAccentBar = false

        spec.layout.primaryLineLimitSmall = 2
        spec.layout.primaryLineLimit = 3
        spec.layout.secondaryLineLimitSmall = 1
        spec.layout.secondaryLineLimit = 1

        spec.style.accent = .yellow
        spec.style.background = .subtleMaterial
        spec.style.backgroundOverlay = .subtleMaterial
        spec.style.backgroundOverlayOpacity = 0
        spec.style.backgroundGlowEnabled = false

        spec.style.nameTextStyle = .caption2
        spec.style.primaryTextStyle = .title2
        spec.style.secondaryTextStyle = .caption

        return spec.normalised()
    }

    static func specFocus() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Focus"
        spec.primaryText = "One thing"
        spec.secondaryText = "Tap to edit"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .teal
        spec.style.background = .plain
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.12
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "sparkles",
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
        spec.primaryText = "In {{__days_until|7}} days"
        spec.secondaryText = "Tap to edit"
        spec.layout.template = .hero
        spec.layout.showsAccentBar = true
        spec.style.accent = .pink
        spec.style.background = .accentGlow
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.10
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "hourglass",
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
        spec.primaryText = "Do the next right thing."
        spec.secondaryText = "Tap to edit"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .orange
        spec.style.background = .plain
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.12
        spec.style.backgroundGlowEnabled = false
        spec.symbol = SymbolSpec(
            name: "quote.bubble.fill",
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
        spec.primaryText = "Checklist"
        spec.secondaryText = "Tap to edit"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .green
        spec.style.background = .plain
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.10
        spec.style.backgroundGlowEnabled = false
        spec.symbol = SymbolSpec(
            name: "checkmark.circle.fill",
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
        spec.primaryText = "Read {{__pages|10}} pages"
        spec.secondaryText = "Tap to edit"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .indigo
        spec.style.background = .plain
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.10
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "book.closed.fill",
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
        spec.primaryText = "{{__steps}}"
        spec.secondaryText = "{{__steps_goal_progress}}"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .green
        spec.style.background = .plain
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.10
        spec.style.backgroundGlowEnabled = false
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
        spec.primaryText = "{{__activity_distance}}"
        spec.secondaryText = "{{__activity_calories}}"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .green
        spec.style.background = .plain
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.10
        spec.style.backgroundGlowEnabled = false
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

    static func specWeather() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Weather"
        spec.primaryText = "{{__weather_temp}}"
        spec.secondaryText = "{{__weather_condition}}"
        spec.layout.template = .classic
        spec.layout.showsAccentBar = true
        spec.style.accent = .blue
        spec.style.background = .plain
        spec.style.backgroundOverlay = .sunset
        spec.style.backgroundOverlayOpacity = 0.10
        spec.style.backgroundGlowEnabled = true
        spec.symbol = SymbolSpec(
            name: "cloud.sun.fill",
            size: 18,
            weight: .semibold,
            renderingMode: .hierarchical,
            tint: .accent,
            placement: .beforeName
        )
        return spec.normalised()
    }

    static func specNextUpCalendar() -> WidgetSpec {
        var spec = WidgetSpec.defaultSpec()
        spec.name = "Next Up"
        spec.primaryText = "{{__calendar_next_title}}"
        spec.secondaryText = "{{__calendar_next_time}}"
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
