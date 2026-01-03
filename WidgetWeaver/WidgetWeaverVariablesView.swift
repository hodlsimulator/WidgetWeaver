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

    @AppStorage("variables.tryit.input") private var tryItInput: String = "Streak: {{streak|0}}"
    @State private var tryItCopied: Bool = false

    var body: some View {
        NavigationStack {
            List {
                headerSection
                tryItSection

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

    private var tryItSection: some View {
        let result = tryItResult
        let outputDisplay: String = {
            if result.isEmptyInput { return "Paste a template above to see its output." }
            if result.output.isEmpty { return "—" }
            return result.output
        }()

        return Section {
            VStack(alignment: .leading, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Input")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    TextEditor(text: $tryItInput)
                        .font(.system(.callout, design: .monospaced))
                        .frame(minHeight: 96)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(alignment: .topLeading) {
                            if tryItInput.isEmpty {
                                Text("e.g. Streak: {{streak|0}}")
                                    .font(.system(.callout, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 14)
                            }
                        }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Quick inserts")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 8)], spacing: 8) {
                        ForEach(tryItSnippets) { snippet in
                            Button {
                                appendTryItSnippet(snippet.value)
                            } label: {
                                Text(snippet.value)
                                    .font(.system(.caption2, design: .monospaced))
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                                    .padding(.vertical, 6)
                                    .padding(.horizontal, 10)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(.thinMaterial, in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Output")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Text(outputDisplay)
                        .font(.system(.callout, design: .monospaced))
                        .foregroundStyle(result.isError ? .red : .primary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                }

                HStack(spacing: 12) {
                    Button {
                        copyTryItOutput()
                    } label: {
                        Label("Copy output", systemImage: "doc.on.doc")
                    }
                    .disabled(result.isEmptyInput)

                    if tryItCopied {
                        Text("Copied")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .transition(.opacity)
                    }

                    Spacer(minLength: 0)
                }
                .animation(.easeInOut(duration: 0.2), value: tryItCopied)
            }
            .padding(.vertical, 4)
        } header: {
            Text("Try it")
        } footer: {
            Text("Uses the same template renderer as widgets. Built-ins (e.g. __steps_*, __activity_* and __weather_*) resolve even without Pro.")
                .font(.caption)
                .foregroundStyle(.secondary)
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

    private struct TryItResult {
        let output: String
        let isError: Bool
        let isEmptyInput: Bool
    }

    private struct TryItSnippet: Identifiable, Hashable {
        let id: String
        let value: String

        init(_ value: String) {
            self.value = value
            self.id = value
        }
    }

    private var tryItSnippets: [TryItSnippet] {
        [
            TryItSnippet("{{streak|0}}"),
            TryItSnippet("{{count|0}}"),
            TryItSnippet("{{done|0}}"),
            TryItSnippet("{{waterMl|0}}"),
            TryItSnippet("{{date.short}}"),
            TryItSnippet("{{time.short}}"),
            TryItSnippet("{{__today}}"),
            TryItSnippet("{{__time}}"),
            TryItSnippet("{{__steps_today|--|number:0}}"),
            TryItSnippet("{{__activity_steps_today|--|number:0}}"),
            TryItSnippet("{{__weather_temp|--}}"),
        ]
    }

    private var tryItResult: TryItResult {
        let raw = tryItInput
        if raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return TryItResult(output: "", isError: false, isEmptyInput: true)
        }

        if hasUnbalancedTemplateDelimiters(raw) {
            return TryItResult(output: "Error: Unbalanced {{ }} in template.", isError: true, isEmptyInput: false)
        }

        let now = WidgetWeaverRenderClock.now

        var vars: [String: String] = proManager.isProUnlocked ? variables : [:]

        let builtIns = WidgetWeaverVariableTemplate.builtInVariables(now: now)
        for (k, v) in builtIns where vars[k] == nil {
            vars[k] = v
        }

        let weatherVars = WidgetWeaverWeatherStore.shared.variablesDictionary(now: now)
        for (k, v) in weatherVars {
            vars[k] = v
        }

        let stepsVars = WidgetWeaverStepsStore.shared.variablesDictionary()
        for (k, v) in stepsVars {
            vars[k] = v
        }

        let activityVars = WidgetWeaverActivityStore.shared.variablesDictionary(now: now)
        for (k, v) in activityVars {
            vars[k] = v
        }

        let rendered = WidgetWeaverVariableTemplate.render(raw, variables: vars, now: now, maxPasses: 3)
        return TryItResult(output: rendered, isError: false, isEmptyInput: false)
    }

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

    private func appendTryItSnippet(_ snippet: String) {
        let trimmed = tryItInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            tryItInput = snippet
            return
        }

        if let last = tryItInput.last, last == "\n" || last == " " {
            tryItInput += snippet
        } else {
            tryItInput += " " + snippet
        }
    }

    private func copyTryItOutput() {
        let result = tryItResult
        guard !result.isEmptyInput else { return }

        UIPasteboard.general.string = result.output

        withAnimation(.easeInOut(duration: 0.15)) {
            tryItCopied = true
        }

        Task {
            try? await Task.sleep(nanoseconds: 900_000_000)
            await MainActor.run {
                withAnimation(.easeInOut(duration: 0.2)) {
                    tryItCopied = false
                }
            }
        }
    }

    private func hasUnbalancedTemplateDelimiters(_ s: String) -> Bool {
        var balance = 0
        var i = s.startIndex
        let end = s.endIndex

        while i < end {
            let ch = s[i]

            if ch == "{" {
                let next = s.index(after: i)
                if next < end, s[next] == "{" {
                    balance += 1
                    i = s.index(after: next)
                    continue
                }
            } else if ch == "}" {
                let next = s.index(after: i)
                if next < end, s[next] == "}" {
                    if balance == 0 { return true }
                    balance -= 1
                    i = s.index(after: next)
                    continue
                }
            }

            i = s.index(after: i)
        }

        return balance != 0
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
