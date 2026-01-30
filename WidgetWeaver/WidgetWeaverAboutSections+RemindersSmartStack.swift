//
//  WidgetWeaverAboutSections+RemindersSmartStack.swift
//  WidgetWeaver
//
//  Created by . . on 1/29/26.
//

import Foundation
import SwiftUI
import WidgetKit

extension WidgetWeaverAboutView {
    // MARK: - Reminders Smart Stack kit

    @ViewBuilder
    var remindersSmartStackSection: some View {
        if WidgetWeaverFeatureFlags.remindersTemplateEnabled {
            Section {
                remindersSmartStackKitIntroRow

                ForEach(remindersSmartStackTemplates) { template in
                    WidgetWeaverAboutTemplateRow(
                        template: template,
                        isProUnlocked: proManager.isProUnlocked,
                        onAdd: { makeDefault in handleAdd(template: template, makeDefault: makeDefault) },
                        onShowPro: onShowPro
                    )
                }
            } header: {
                WidgetWeaverAboutSectionHeader("Smart Stack Kit", systemImage: "square.stack.3d.up.fill", accent: .orange)
            } footer: {
                Text("Smart Stack v2 (enabled when the kit designs are added/upgraded via ‘Add all 6’) assigns each reminder to the first matching page, with no duplicates per refresh.\nPrecedence: Overdue → Today → Upcoming → High priority → Anytime → Lists. Upcoming is tomorrow through the next 7 days (never Today). Lists is the remainder (never repeats items already shown).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var remindersSmartStackTemplates: [WidgetWeaverAboutTemplate] {
        let desiredIDs = [
            "starter-reminders-today",
            "starter-reminders-overdue",
            "starter-reminders-soon",
            "starter-reminders-priority",
            "starter-reminders-focus",
            "starter-reminders-list",
        ]

        let byID = Dictionary(uniqueKeysWithValues: Self.starterTemplates.map { ($0.id, $0) })
        return desiredIDs.compactMap { byID[$0] }
    }

    private var remindersSmartStackKitIntroRow: some View {
        WidgetWeaverAboutCard(accent: .orange) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    ZStack {
                        Circle()
                            .fill(Color.orange.opacity(0.16))

                        Circle()
                            .strokeBorder(Color.orange.opacity(0.26), lineWidth: 1)

                        Image(systemName: "square.stack.3d.up.fill")
                            .font(.system(size: 14, weight: .semibold, design: .rounded))
                            .foregroundStyle(.orange)
                    }
                    .frame(width: 28, height: 28)
                    .padding(.top, 1)
                    .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text("Reminders Smart Stack")
                                .font(.headline)

                            WidgetWeaverAboutBadge("6 designs", accent: .orange)
                        }

                        Text("Six Reminders templates designed to be stacked together in one Smart Stack. In Smart Stack v2 (enabled for the kit designs after ‘Add all 6’), each reminder is assigned to the first matching page (Overdue → Today → Upcoming → High priority → Anytime → Lists), with no duplicates per refresh.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)
                }

                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 10) {
                        remindersSmartStackKitAddAllButton
                        remindersSmartStackKitGuideButton
                    }

                    VStack(alignment: .leading, spacing: 10) {
                        remindersSmartStackKitAddAllButton
                        remindersSmartStackKitGuideButton
                    }
                }
            }
        }
        .tint(.orange)
        .wwAboutListRow()
    }

    private var remindersSmartStackKitAddAllButton: some View {
        Button {
            handleAddRemindersSmartStackKit()
        } label: {
            Label("Add all 6", systemImage: "plus")
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.small)
    }

    private var remindersSmartStackKitGuideButton: some View {
        Button {
            onShowRemindersSmartStackGuide()
        } label: {
            Label("Guide", systemImage: "book.fill")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}
