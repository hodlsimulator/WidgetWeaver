//
//  WidgetWeaverAboutCatalog+Reminders.swift
//  WidgetWeaver
//
//  Created by . . on 1/21/26.
//

import Foundation
import SwiftUI
import WidgetKit

extension WidgetWeaverAboutView {
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
        spec.layout.showsAccentBar = true
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
}
