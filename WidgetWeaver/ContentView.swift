//
//  ContentView.swift
//  WidgetWeaver
//
//  Created by . . on 12/16/25.
//

import SwiftUI
import WidgetKit

struct ContentView: View {
    @State private var name: String = ""
    @State private var primaryText: String = ""
    @State private var secondaryText: String = ""

    @State private var lastSavedAt: Date?

    private let store = WidgetSpecStore.shared

    var body: some View {
        NavigationStack {
            Form {
                Section("Spec") {
                    TextField("Name", text: $name)
                        .textInputAutocapitalization(.words)

                    TextField("Primary text", text: $primaryText)

                    TextField("Secondary text (optional)", text: $secondaryText)
                }

                Section {
                    Button("Save to Widget") {
                        save()
                    }
                    .disabled(primaryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                    Button("Load Saved") {
                        load()
                    }

                    Button("Reset to Default", role: .destructive) {
                        resetToDefault()
                    }
                }

                if let lastSavedAt {
                    Section("Status") {
                        Text("Saved: \(lastSavedAt.formatted(date: .abbreviated, time: .standard))")
                    }
                }
            }
            .navigationTitle("WidgetWeaver")
            .onAppear {
                load()
            }
        }
    }

    private func load() {
        let spec = store.load()
        name = spec.name
        primaryText = spec.primaryText
        secondaryText = spec.secondaryText ?? ""
    }

    private func save() {
        var spec = WidgetSpec(
            name: name,
            primaryText: primaryText,
            secondaryText: secondaryText.isEmpty ? nil : secondaryText,
            updatedAt: Date()
        )
        spec = spec.normalised()

        store.save(spec)
        lastSavedAt = spec.updatedAt

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
    }

    private func resetToDefault() {
        let spec = WidgetSpec.defaultSpec()
        store.save(spec)
        lastSavedAt = Date()
        load()

        WidgetCenter.shared.reloadTimelines(ofKind: WidgetWeaverWidgetKinds.main)
    }
}
