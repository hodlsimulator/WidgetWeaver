//
//  WidgetWeaverVariablesView.swift
//  WidgetWeaver
//
//  Created by . . on 12/18/25.
//

import SwiftUI
import UIKit

struct WidgetWeaverVariablesView: View {
    @ObservedObject var proManager: WidgetWeaverProManager
    let onShowPro: @MainActor () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var variables: [String: String] = [:]
    @State private var searchText: String = ""

    @State private var newKey: String = ""
    @State private var newValue: String = ""

    @State private var statusMessage: String = ""
    @State private var showClearConfirmation: Bool = false

    var body: some View {
        NavigationStack {
            List {
                headerSection

                if proManager.isProUnlocked {
                    addSection
                    variablesSection
                    toolsSection
                } else {
                    lockedSection
                }
            }
            .navigationTitle("Variables")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, placement: .navigationBarDrawer(displayMode: .automatic))
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                }
            }
            .confirmationDialog(
                "Clear all variables?",
                isPresented: $showClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Clear All", role: .destructive) { clearAll() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This removes all saved variables from the App Group.\nWidgets will update after clearing.")
            }
            .onAppear { refresh() }
            .onChange(of: proManager.isProUnlocked) { _, _ in refresh() }
        }
    }

    // MARK: - Sections

    private var headerSection: some View {
        Section {
            Text(
                """
                Variables let text fields pull values at render time.

                Basic:
                {{key}}  •  {{key|fallback}}

                Filters:
                {{amount|0|number:0}}
                {{last_done|Never|relative}}
                {{progress|0|bar:10}}

                Built-ins:
                {{__now||date:HH:mm}}  •  {{__today}}
                
                Weather:
                {{__weather_temp}}°  •  {{__weather_condition}}
                H {{__weather_high}}°  •  L {{__weather_low}}°  •  {{__weather_precip|0|number:0}}%
                """
            )
            .font(.subheadline)
            .foregroundStyle(.secondary)

            HStack(alignment: .top, spacing: 12) {
                Text(
                    """
                    Example:
                    Streak: {{streak|0}} {{streak|0|plural:day:days}}
                    Last done: {{last_done|Never|relative}}
                    Progress: {{progress|0|bar:10}}
                    """
                )
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)

                Spacer(minLength: 0)

                Button {
                    UIPasteboard.general.string =
                    "Streak: {{streak|0}} {{streak|0|plural:day:days}}\nLast done: {{last_done|Never|relative}}\nProgress: {{progress|0|bar:10}}"
                    statusMessage = "Copied example."
                } label: {
                    Label("Copy", systemImage: "doc.on.doc")
                }
                .controlSize(.small)
            }

            if !statusMessage.isEmpty {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("How it works")
        }
    }

    private var lockedSection: some View {
        Section {
            Label("Variables require WidgetWeaver Pro.", systemImage: "lock.fill")
                .foregroundStyle(.secondary)

            Text("Unlock Pro to manage variables in-app and update widgets via Shortcuts.")
                .font(.caption)
                .foregroundStyle(.secondary)

            Button {
                Task { @MainActor in onShowPro() }
            } label: {
                Label("Unlock Pro", systemImage: "crown.fill")
            }
        } header: {
            Text("Pro")
        }
    }

    private var addSection: some View {
        Section {
            TextField("Key (e.g. streak)", text: $newKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            TextField("Value", text: $newValue)

            Button { addVariable() } label: {
                Label("Add Variable", systemImage: "plus.circle.fill")
            }
            .disabled(WidgetWeaverVariableStore.canonicalKey(newKey).isEmpty)
        } header: {
            Text("Add")
        } footer: {
            Text("Keys are canonicalised (trimmed, lowercased, internal whitespace collapsed).")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var variablesSection: some View {
        Section {
            if filteredKeys.isEmpty {
                Text(searchText.isEmpty ? "No variables yet." : "No matches.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(filteredKeys, id: \.self) { key in
                    NavigationLink {
                        WidgetWeaverVariableDetailView(
                            key: key,
                            initialValue: variables[key] ?? "",
                            onSave: { value in
                                WidgetWeaverVariableStore.shared.setValue(value, for: key)
                                refresh()
                            },
                            onDelete: {
                                WidgetWeaverVariableStore.shared.removeValue(for: key)
                                refresh()
                            }
                        )
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(key)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)

                                Text(variables[key] ?? "")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }

                            Spacer(minLength: 0)

                            Button {
                                UIPasteboard.general.string = "{{\(key)}}"
                                statusMessage = "Copied {{\(key)}}."
                            } label: {
                                Image(systemName: "curlybraces")
                                    .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Copy template")
                        }
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                        Button(role: .destructive) {
                            WidgetWeaverVariableStore.shared.removeValue(for: key)
                            refresh()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        } header: {
            Text("Variables (\(variables.count))")
        } footer: {
            Text("Tap a variable to edit. Swipe to delete.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var toolsSection: some View {
        Section {
            Button(role: .destructive) { showClearConfirmation = true } label: {
                Label("Clear All Variables", systemImage: "trash")
            }
        } header: {
            Text("Tools")
        }
    }

    // MARK: - Helpers

    private var filteredKeys: [String] {
        let keys = variables.keys.sorted()
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if q.isEmpty { return keys }
        return keys.filter {
            $0.lowercased().contains(q) || (variables[$0] ?? "").lowercased().contains(q)
        }
    }

    private func refresh() {
        if proManager.isProUnlocked {
            variables = WidgetWeaverVariableStore.shared.loadAll()
        } else {
            variables = [:]
        }
    }

    private func addVariable() {
        let canonical = WidgetWeaverVariableStore.canonicalKey(newKey)
        guard !canonical.isEmpty else { return }

        WidgetWeaverVariableStore.shared.setValue(newValue, for: canonical)
        newKey = ""
        newValue = ""
        statusMessage = "Saved \(canonical)."
        refresh()
    }

    private func clearAll() {
        WidgetWeaverVariableStore.shared.clearAll()
        statusMessage = "Cleared all variables."
        refresh()
    }
}

private struct WidgetWeaverVariableDetailView: View {
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
                LabeledContent("Key", value: key)

                Button {
                    UIPasteboard.general.string = "{{\(key)}}"
                    statusMessage = "Copied {{\(key)}}."
                } label: {
                    Label("Copy template {{\(key)}}", systemImage: "doc.on.doc")
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Template")
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
                Button {
                    let now = Date()
                    value = WidgetWeaverVariableTemplate.iso8601String(now)
                    onSave(value)
                    statusMessage = "Set to now."
                } label: {
                    Label("Set to Now (ISO8601)", systemImage: "clock")
                }

                Button {
                    value = String(Int64(Date().timeIntervalSince1970))
                    onSave(value)
                    statusMessage = "Set to unix seconds."
                } label: {
                    Label("Set to Now (Unix seconds)", systemImage: "timer")
                }
            } header: {
                Text("Quick date/time")
            } footer: {
                Text("Handy for {{\(key)|Never|relative}} or {{\(key)||date:EEE d MMM}}.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Stepper("Amount: \(incrementAmount)", value: $incrementAmount, in: 1...999)

                Button {
                    let existing = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    let newValue = existing + incrementAmount
                    value = String(newValue)
                    onSave(value)
                    statusMessage = "Incremented to \(newValue)."
                } label: {
                    Label("Increment", systemImage: "plus.circle")
                }

                Button {
                    let existing = Int(value.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
                    let newValue = existing - incrementAmount
                    value = String(newValue)
                    onSave(value)
                    statusMessage = "Decremented to \(newValue)."
                } label: {
                    Label("Decrement", systemImage: "minus.circle")
                }
            } header: {
                Text("Quick maths")
            } footer: {
                Text("Increment/decrement treats the value as an integer (non-numbers become 0).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(role: .destructive) {
                    onDelete()
                    dismiss()
                } label: {
                    Label("Delete Variable", systemImage: "trash")
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
