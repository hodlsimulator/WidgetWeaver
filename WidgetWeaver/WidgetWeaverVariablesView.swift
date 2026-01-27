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

    private enum FocusedField: Hashable {
        case tryItInput
        case newName
        case newTextValue
    }

    private enum NewValueKind: String, CaseIterable, Identifiable {
        case number = "Number"
        case text = "Text"
        case yesNo = "Yes/No"
        case dateTime = "Date & time"

        var id: String { rawValue }

        var systemImage: String {
            switch self {
            case .number: return "number"
            case .text: return "textformat"
            case .yesNo: return "checkmark.circle"
            case .dateTime: return "clock"
            }
        }

        var helperText: String {
            switch self {
            case .number:
                return "Good for counters (streaks, score, water ml)."
            case .text:
                return "Good for names, labels, or short notes."
            case .yesNo:
                return "Stores 1 for Yes, 0 for No."
            case .dateTime:
                return "Saved as ISO8601 for relative/date filters."
            }
        }
    }

    @FocusState private var focusedField: FocusedField?

    @State private var variables: [String: String] = [:]
    @State private var searchText: String = ""

    @State private var newName: String = ""
    @State private var newValueKind: NewValueKind = .number
    @State private var newTextValue: String = ""
    @State private var newNumberValue: Int = 0
    @State private var newYesNoValue: Bool = false
    @State private var newDateValue: Date = Date()

    @State private var statusMessage: String = ""
    @State private var showClearConfirmation: Bool = false

    @State private var showInsertPicker: Bool = false
    @State private var showTemplateBuilder: Bool = false

    @AppStorage("variables.help.showAdvanced") private var showAdvancedHelp: Bool = false
    @AppStorage("variables.tryit.input") private var tryItInput: String = "Streak: {{streak|0}}"
    @State private var tryItCopied: Bool = false

    var body: some View {
        NavigationStack {
            List {
                guideSection
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

                ToolbarItemGroup(placement: .keyboard) {
                    if focusedField == .tryItInput || focusedField == .newTextValue {
                        Spacer()

                        Button {
                            showTemplateBuilder = false
                            showInsertPicker = true
                        } label: {
                            Label("Insert variable", systemImage: "curlybraces.square")
                        }

                        Button {
                            showInsertPicker = false
                            showTemplateBuilder = true
                        } label: {
                            Label("Build snippet", systemImage: "wand.and.stars")
                        }
                    }
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
                Text("This removes all saved variables from the App Group. Widgets will update after clearing.")
            }
            .sheet(isPresented: $showInsertPicker) {
                NavigationStack {
                    WidgetWeaverVariableInsertPickerView(
                        isProUnlocked: proManager.isProUnlocked,
                        customVariables: variables,
                        onInsert: { snippet in
                            insertSnippet(snippet)
                        }
                    )
                }
            }
            .sheet(isPresented: $showTemplateBuilder) {
                NavigationStack {
                    WidgetWeaverVariableTemplateBuilderView(
                        isProUnlocked: proManager.isProUnlocked,
                        customVariables: variables,
                        onInsert: { snippet in
                            insertSnippet(snippet)
                        }
                    )
                }
            }
            .onAppear { refresh() }
            .onChange(of: proManager.isProUnlocked) { _, _ in refresh() }
        }
    }

    // MARK: - Sections

    private var guideSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 12) {
                Text("Variables are saved values (like a counter or a name). Widgets can show them inside text.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(alignment: .leading, spacing: 8) {
                    Label("Add a variable below (for example: streak = 3).", systemImage: "1.circle")
                    Label("Use “Build snippet” or “Insert variable” instead of typing {{ }}.", systemImage: "2.circle")
                    Label("Widgets refresh automatically when a variable changes.", systemImage: "3.circle")
                }
                .font(.subheadline)

                ControlGroup {
                    Button {
                        focusedField = .tryItInput
                        showInsertPicker = false
                        showTemplateBuilder = true
                    } label: {
                        Label("Build a snippet…", systemImage: "wand.and.stars")
                    }

                    Button {
                        focusedField = .tryItInput
                        showTemplateBuilder = false
                        showInsertPicker = true
                    } label: {
                        Label("Insert variable…", systemImage: "curlybraces.square")
                    }
                }
                .controlSize(.regular)

                Toggle("Show advanced syntax", isOn: $showAdvancedHelp)

                if showAdvancedHelp {
                    advancedHelpBody
                }

                if !statusMessage.isEmpty {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Text("Quick guide")
        }
    }

    private var advancedHelpBody: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(
                """
                Basics:
                {{key}}  •  {{key|fallback}}

                Common styles:
                {{amount|0|number:0}}
                {{last_done|Never|relative}}
                {{progress|0|bar:10}}

                Built-ins (always available):
                {{__time}}  •  {{__today}}  •  {{__weekday}}
                """
            )
            .font(.system(.caption, design: .monospaced))
            .foregroundStyle(.secondary)
            .textSelection(.enabled)

            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text("Example: Streak: {{streak|0}} {{streak|0|plural:day:days}}")
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
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
        }
    }

    private var tryItSection: some View {
        let result = tryItResult
        let outputDisplay: String = {
            if result.isEmptyInput { return "Paste a snippet above to see its output." }
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
                        .focused($focusedField, equals: .tryItInput)
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

                    WidgetWeaverVariableSnippetChipsRow(
                        isProUnlocked: proManager.isProUnlocked,
                        defaults: tryItQuickInsertDefaults,
                        onInsert: { snippet in
                            insertSnippet(snippet)
                        },
                        onOpenPicker: {
                            showTemplateBuilder = false
                            showInsertPicker = true
                        }
                    )
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

            Button {
                focusedField = .tryItInput
                showInsertPicker = false
                showTemplateBuilder = true
            } label: {
                Label("Build snippet…", systemImage: "wand.and.stars")
            }

            Button {
                focusedField = .tryItInput
                showTemplateBuilder = false
                showInsertPicker = true
            } label: {
                Label("Insert variable…", systemImage: "curlybraces.square")
            }

            NavigationLink {
                WidgetWeaverBuiltInKeysView(tryItInput: $tryItInput)
            } label: {
                Label("Browse built-in keys", systemImage: "list.bullet")
            }
        } header: {
            Text("Try it")
        } footer: {
            Text("Uses the same template renderer as widgets. Built-ins (for example: __time and __today) work without Pro.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var lockedSection: some View {
        Section {
            Text("Custom variables are a Pro feature.")
                .foregroundStyle(.secondary)

            Button {
                Task { @MainActor in
                    onShowPro()
                }
            } label: {
                Label("Unlock Pro", systemImage: "sparkles")
            }
        } header: {
            Text("Pro")
        }
    }

    private var addSection: some View {
        let key = WidgetWeaverVariableStore.canonicalKey(newName)
        let templateSnippet = key.isEmpty ? "" : "{{\(key)}}"

        return Section {
            TextField("Name (for example: streak)", text: $newName)
                .focused($focusedField, equals: .newName)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled(true)

            if !templateSnippet.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Template")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Text(templateSnippet)
                            .font(.system(.callout, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    Spacer(minLength: 0)

                    Button {
                        UIPasteboard.general.string = templateSnippet
                        statusMessage = "Copied \(templateSnippet)."
                    } label: {
                        Label("Copy", systemImage: "doc.on.doc")
                    }
                    .controlSize(.small)
                }
            }

            Picker("Value type", selection: $newValueKind) {
                ForEach(NewValueKind.allCases) { kind in
                    Label(kind.rawValue, systemImage: kind.systemImage).tag(kind)
                }
            }

            newValueEditor

            Button {
                addVariable()
            } label: {
                Label("Save variable", systemImage: "plus.circle.fill")
            }
            .disabled(key.isEmpty)
        } header: {
            Text("Add a variable")
        } footer: {
            VStack(alignment: .leading, spacing: 6) {
                Text("The name becomes the key inside {{ }}.")
                Text(newValueKind.helperText)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var newValueEditor: some View {
        switch newValueKind {
        case .number:
            Stepper("Value: \(newNumberValue)", value: $newNumberValue, in: -999_999...999_999)

        case .text:
            TextField("Value", text: $newTextValue, axis: .vertical)
                .focused($focusedField, equals: .newTextValue)
                .lineLimit(3, reservesSpace: true)

        case .yesNo:
            Toggle("Value", isOn: $newYesNoValue)

        case .dateTime:
            DatePicker("Date & time", selection: $newDateValue, displayedComponents: [.date, .hourAndMinute])
            Button {
                newDateValue = Date()
                statusMessage = "Set date/time to now."
            } label: {
                Label("Set to now", systemImage: "clock")
            }
            .controlSize(.small)
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
                        variableRow(key: key, value: variables[key] ?? "")
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

    private func variableRow(key: String, value: String) -> some View {
        let icon = iconName(forValue: value)
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let displayValue = trimmed.isEmpty ? "—" : trimmed

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Image(systemName: icon)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(key)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Text(displayValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 0)

            Button {
                let snippet = "{{\(key)}}"
                UIPasteboard.general.string = snippet
                statusMessage = "Copied \(snippet)."
            } label: {
                Label("Copy", systemImage: "doc.on.doc")
            }
            .labelStyle(.titleAndIcon)
            .font(.caption)
            .controlSize(.small)
            .buttonStyle(.borderless)
            .accessibilityLabel("Copy template")
        }
    }

    private var toolsSection: some View {
        Section {
            Button(role: .destructive) { showClearConfirmation = true } label: {
                Label("Clear all variables", systemImage: "trash")
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

    private var tryItQuickInsertDefaults: [String] {
        [
            "{{streak|0}}",
            "{{count|0}}",
            "{{done|0}}",
            "{{waterMl|0}}",
            "{{__today}}",
            "{{__time}}",
            "{{__weekday}}",
            "{{__steps_today|--|number:0}}",
            "{{__activity_steps_today|--|number:0}}",
            "{{__weather_temp|--}}",
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
        let canonical = WidgetWeaverVariableStore.canonicalKey(newName)
        guard !canonical.isEmpty else { return }

        let valueToSave: String
        switch newValueKind {
        case .number:
            valueToSave = String(newNumberValue)
        case .text:
            valueToSave = newTextValue
        case .yesNo:
            valueToSave = newYesNoValue ? "1" : "0"
        case .dateTime:
            valueToSave = WidgetWeaverVariableTemplate.iso8601String(newDateValue)
        }

        WidgetWeaverVariableStore.shared.setValue(valueToSave, for: canonical)

        newName = ""
        newTextValue = ""
        newNumberValue = 0
        newYesNoValue = false
        newDateValue = Date()

        statusMessage = "Saved \(canonical)."
        refresh()
    }

    private func clearAll() {
        WidgetWeaverVariableStore.shared.clearAll()
        statusMessage = "Cleared all variables."
        refresh()
    }

    private func insertSnippet(_ snippet: String) {
        switch focusedField {
        case .newTextValue:
            newTextValue = appendingSnippet(snippet, to: newTextValue)

        default:
            tryItInput = appendingSnippet(snippet, to: tryItInput)
        }
    }

    private func appendingSnippet(_ snippet: String, to text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return snippet
        }

        if let last = text.last, last == "\n" || last == " " {
            return text + snippet
        }

        return text + " " + snippet
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

    private func iconName(forValue rawValue: String) -> String {
        let s = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return "questionmark.circle" }

        if s == "0" || s == "1" { return "checkmark.circle" }

        if Int(s) != nil { return "number" }

        if looksLikeISO8601(s) || looksLikeUnixSeconds(s) {
            return "clock"
        }

        return "textformat"
    }

    private func looksLikeISO8601(_ s: String) -> Bool {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if f.date(from: s) != nil { return true }

        let f2 = ISO8601DateFormatter()
        f2.formatOptions = [.withInternetDateTime]
        return f2.date(from: s) != nil
    }

    private func looksLikeUnixSeconds(_ s: String) -> Bool {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 10, trimmed.count <= 13 else { return false }
        guard let i = Int64(trimmed) else { return false }
        return i >= 1_000_000_000 && i <= 4_100_000_000
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
