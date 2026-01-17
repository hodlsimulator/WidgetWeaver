//
//  WidgetWeaverRemindersSmartStackGuideView.swift
//  WidgetWeaver
//
//  Created by . . on 1/17/26.
//

import SwiftUI

struct WidgetWeaverRemindersSmartStackGuideView: View {
    let onClose: (() -> Void)?

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 12) {
                    Text("Reminders Smart Stack")
                        .font(.title3.weight(.semibold))

                    Text("A six-widget set designed to be used together in a Smart Stack.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    GroupBox {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Already have a Smart Stack?")
                                .font(.subheadline.weight(.semibold))

                            Text("Skip straight to steps 3–4 to grant access and refresh the snapshot.")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Setup (5 steps)") {
                WidgetWeaverAboutBulletList(items: [
                    "Create a Smart Stack and add 6 WidgetWeaver widgets (any size).",
                    "Edit each widget and select a different design: \"Reminders 1 — Today\" through \"Reminders 6 — Lists\".",
                    "In WidgetWeaver, open Reminders settings and grant Full Access.",
                    "Refresh the Reminders snapshot in the app so widgets can update.",
                    "If tap-to-complete looks disabled or items don’t update, open the app again and refresh the snapshot."
                ])
            }

            Section("Notes") {
                WidgetWeaverAboutBulletList(items: [
                    "Widgets render cached snapshots only (no direct Reminders reads).",
                    "Tap-to-complete requires Reminders Full Access and a recent snapshot refresh.",
                    "“Add all 6” is safe to run again; it only creates missing designs by default.",
                    "This guide can be reopened from Explore → Templates (Reminders) → Guide.",
                    "The six designs are numbered so they sort together in widget configuration."
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
