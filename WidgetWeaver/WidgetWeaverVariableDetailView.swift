//
//  WidgetWeaverVariableDetailView.swift
//  WidgetWeaver
//
//  Created by . . on 1/27/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverVariableDetailView: View {
    let key: String
    let initialValue: String

    let onSave: (String) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var value: String = ""
    @State private var incrementAmount: Int = 1
    @State private var statusMessage: String = ""

    var body: some View {
        List {
            Section {
                LabeledContent("Name", value: key)

                Button {
                    UIPasteboard.general.string = "{{\(key)}}"
                    statusMessage = "Copied {{\(key)}}."
                } label: {
                    Label("Copy template", systemImage: "doc.on.doc")
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Use in text")
            }

            Section {
                TextField("Value", text: $value, axis: .vertical)
                    .lineLimit(3, reservesSpace: true)

                Button {
                    onSave(value)
                    statusMessage = "Saved."
                } label: {
                    Label("Save", systemImage: "checkmark.circle.fill")
                }
            } header: {
                Text("Value")
            }

            Section {
                Stepper("Amount: \(incrementAmount)", value: $incrementAmount, in: 1...999)

                HStack(spacing: 12) {
                    Button {
                        let existing = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                        let newValue = existing - incrementAmount
                        value = String(newValue)
                        onSave(value)
                        statusMessage = "Decremented to \(newValue)."
                    } label: {
                        Label("Minus", systemImage: "minus.circle")
                    }

                    Button {
                        let existing = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                        let newValue = existing + incrementAmount
                        value = String(newValue)
                        onSave(value)
                        statusMessage = "Incremented to \(newValue)."
                    } label: {
                        Label("Plus", systemImage: "plus.circle")
                    }
                }
            } header: {
                Text("Quick change")
            } footer: {
                Text("Plus/minus treats the value as an integer (non-numbers become 0).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button {
                    let now = Date()
                    value = WidgetWeaverVariableTemplate.iso8601String(now)
                    onSave(value)
                    statusMessage = "Set to now."
                } label: {
                    Label("Set to now (ISO8601)", systemImage: "clock")
                }

                Button {
                    value = String(Int64(Date().timeIntervalSince1970))
                    onSave(value)
                    statusMessage = "Set to unix seconds."
                } label: {
                    Label("Set to now (unix seconds)", systemImage: "timer")
                }
            } header: {
                Text("Quick date/time")
            } footer: {
                Text("Useful for {{\(key)|Never|relative}} or {{\(key)||date:EEE d MMM}}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Delete variable", systemImage: "trash")
                }
            }
        }
        .navigationTitle(key)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { value = initialValue }
    }
}
