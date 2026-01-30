//
//  WidgetWeaverRemindersSmartStackGuideView.swift
//  WidgetWeaver
//
//  Created by . . on 1/17/26.
//

import SwiftUI

struct WidgetWeaverRemindersSmartStackGuideView: View {
    let onClose: (() -> Void)?

    private let dragToCreateStackDiagram = """
Two widgets (same size)
┌─────────┐  ┌─────────┐
│ Today   │  │ Overdue │
└─────────┘  └─────────┘

Drag one widget directly on top of the other
        ↓ (release when the tile highlights)
     ┌─────────┐
     │ Stack   │
     │ Today   │
     └─────────┘
"""

    private let dragToAddMoreWidgetsDiagram = """
Add more widgets to the existing stack
┌─────────┐  +  ┌─────────┐
│ Stack   │     │ Upcoming│
└─────────┘     └─────────┘
        drag Upcoming onto Stack
                ↓
          (Stack now has 3)
"""

    private let v2PrecedenceDiagram = """
Smart Stack v2 (no duplicates per refresh)
Overdue → Today → Upcoming → High priority → Anytime → Lists
"""

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reminders Smart Stack")
                        .font(.title3.weight(.semibold))

                    Text("A six-widget set designed to be used together in one Smart Stack on the Home Screen.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("What is a Smart Stack?")
                                .font(.subheadline.weight(.semibold))

                            Text("A Smart Stack is one widget tile that contains multiple widgets. Swipe up/down on the tile to switch between Overdue, Today, Upcoming, High priority, Anytime, and Lists.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("One rule: all widgets must be the same size")
                                .font(.subheadline.weight(.semibold))

                            Text("Stacks only work when every widget is the same size (Small, Medium, or Large). If sizes are mixed, iOS will move the widget instead of stacking it.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Already have a stack?")
                                .font(.subheadline.weight(.semibold))

                            Text("If the widgets are already stacked, skip to Step 5 to grant Full Access and refresh the snapshot.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Step 1 — Prepare the six designs in WidgetWeaver") {
                WidgetWeaverAboutBulletList(items: [
                    "Open Explore → Templates (Reminders) → Reminders Smart Stack.",
                    "Tap “Add all 6” to upgrade any existing Smart Stack designs to v2 in place, and add any missing pages (safe to run again).",
                    "The six pages are: Overdue, Today, Upcoming, High priority, Anytime, and Lists."
                ])
            }

            Section("How the pages work") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Smart Stack v2 assigns every reminder to exactly one page on each refresh (no duplicates). If a reminder matches multiple pages, the first match wins.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    WidgetWeaverAboutCodeBlock(v2PrecedenceDiagram, accent: .orange)

                    WidgetWeaverAboutBulletList(items: [
                        "Overdue: due before today (local day).",
                        "Today: due today (local day).",
                        "Upcoming: due tomorrow through the next 7 days (never Today).",
                        "High priority: priority 1–4 reminders that are not already shown in Overdue, Today, or Upcoming.",
                        "Anytime: reminders with no due date (excluding anything already shown above).",
                        "Lists: the remainder only, grouped by list (never repeats items already shown)."
                    ])
                }
                .padding(.vertical, 4)
            }

            Section("Step 2 — Add WidgetWeaver widgets to the Home Screen") {
                WidgetWeaverAboutBulletList(items: [
                    "On the Home Screen, touch and hold an empty area until the icons start wiggling (edit mode).",
                    "Tap the “+” button (top-left), search for WidgetWeaver, and pick the “WidgetWeaver” widget.",
                    "Choose one size (Small / Medium / Large) and tap “Add Widget”.",
                    "Repeat until there are 6 WidgetWeaver widgets on the Home Screen (all the same size)."
                ])
            }

            Section("Step 3 — Set a different design for each widget") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("This is easiest before stacking, while the widgets are still separate.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    WidgetWeaverAboutBulletList(items: [
                        "Touch and hold a WidgetWeaver widget, then choose “Edit Widget”.",
                        "Open “Design” and select one of the six numbered Reminders Smart Stack designs (one per widget).",
                        "Recommended set: Reminders 1 — Today, Reminders 2 — Overdue, Reminders 3 — Upcoming, Reminders 4 — High priority, Reminders 5 — Anytime, Reminders 6 — Lists."
                    ])
                }
                .padding(.vertical, 4)
            }

            Section("Step 4 — Create the Smart Stack by dragging") {
                VStack(alignment: .leading, spacing: 12) {
                    Text("In edit mode, one widget becomes a Smart Stack when another widget is dragged on top of it.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    WidgetWeaverAboutBulletList(items: [
                        "Enter Home Screen edit mode (icons wiggling).",
                        "Touch and hold the widget to move until it lifts, keeping the finger down while dragging.",
                        "Drag it directly on top of another WidgetWeaver widget of the same size.",
                        "Pause for a moment. When the destination tile highlights (usually a grey outline / “Stack” cue), lift the finger to drop.",
                        "Repeat for the remaining four widgets, dragging each one onto the existing stack.",
                        "Tap Done to leave edit mode."
                    ])

                    WidgetWeaverAboutCodeBlock(dragToCreateStackDiagram, accent: .orange)

                    WidgetWeaverAboutCodeBlock(dragToAddMoreWidgetsDiagram, accent: .orange)
                }
                .padding(.vertical, 4)
            }

            Section("Step 5 — Grant Reminders Full Access and refresh the snapshot") {
                WidgetWeaverAboutBulletList(items: [
                    "Open WidgetWeaver.",
                    "Open Reminders settings (toolbar → “Reminders settings”).",
                    "Under “Reminders access”, tap “Request Full Access” and accept the system prompt.",
                    "Under “Snapshot cache (App Group)”, tap “Refresh snapshot now”.",
                    "Return to the Home Screen. Widgets update on an iOS schedule; opening the app again can help if updates are delayed."
                ])
            }

            Section("Troubleshooting") {
                WidgetWeaverAboutBulletList(items: [
                    "Dragging does not create a stack: confirm both widgets are the same size and the Home Screen is in edit mode.",
                    "Design choices are missing: run “Add all 6” again so the six designs exist in the Library.",
                    "Widgets look blank or stuck on old data: open Reminders settings and use “Refresh snapshot now” again.",
                    "Tap-to-complete looks disabled: Full Access must be granted and a recent snapshot must be cached."
                ])
            }

            Section("Notes") {
                WidgetWeaverAboutBulletList(items: [
                    "Widgets render cached snapshots only (no direct Reminders reads in the widget extension).",
                    "The six designs are numbered so they sort together in widget configuration.",
                    "This guide can be reopened from Explore → Templates (Reminders) → Guide."
                ])
            }
        }
        .navigationTitle("Smart Stack Setup")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if let onClose {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { onClose() }
                }
            }
        }
    }
}
