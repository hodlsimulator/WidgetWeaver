//
//  WidgetWeaverAboutSections+Templates.swift
//  WidgetWeaver
//
//  Created by . . on 1/29/26.
//

import Foundation
import SwiftUI
import WidgetKit

extension WidgetWeaverAboutView {
    // MARK: - Starter templates

    var starterTemplatesSection: some View {
        let remindersEnabled = WidgetWeaverFeatureFlags.remindersTemplateEnabled
        let templates = Self.starterTemplates.filter { template in
            if remindersEnabled {
                return template.id != "starter-list" && !template.id.hasPrefix("starter-reminders-")
            }
            return !template.id.hasPrefix("starter-reminders-")
        }

        return Section {
            ForEach(templates) { template in
                WidgetWeaverAboutTemplateRow(
                    template: template,
                    isProUnlocked: proManager.isProUnlocked,
                    onAdd: { makeDefault in handleAdd(template: template, makeDefault: makeDefault) },
                    onShowPro: onShowPro
                )
            }
        } header: {
            WidgetWeaverAboutSectionHeader("Templates", systemImage: "square.grid.2x2.fill", accent: .pink)
        } footer: {
            Text("Templates are added to your Library as Designs. Edit them any time.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Pro templates

    var proTemplatesSection: some View {
        Section {
            ForEach(Self.proTemplates) { template in
                WidgetWeaverAboutTemplateRow(
                    template: template,
                    isProUnlocked: proManager.isProUnlocked,
                    onAdd: { makeDefault in handleAdd(template: template, makeDefault: makeDefault) },
                    onShowPro: onShowPro
                )
            }
        } header: {
            WidgetWeaverAboutSectionHeader("Pro Templates", systemImage: "crown.fill", accent: .yellow)
        } footer: {
            Text("Pro templates showcase buttons, variables, and matched sets.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}
