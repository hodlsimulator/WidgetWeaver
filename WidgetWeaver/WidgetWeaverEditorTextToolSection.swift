//
//  WidgetWeaverEditorTextToolSection.swift
//  WidgetWeaver
//
//  Created by . . on 1/25/26.
//

import SwiftUI
import UIKit

struct WidgetWeaverEditorTextToolSection: View {
    @Binding var designName: String
    @Binding var primaryText: String
    @Binding var secondaryText: String

    let matchedSetEnabled: Bool
    let editingFamilyLabel: String
    let isProUnlocked: Bool
    let onOpenVariables: (() -> Void)?

    @FocusState private var focusedField: FocusedField?
    @State private var showInsertPicker: Bool = false
    @State private var insertTarget: InsertTarget = .primary

    @State private var primaryInsertionRequest: WWTextInsertionRequest?
    @State private var secondaryInsertionRequest: WWTextInsertionRequest?
    @State private var restoreFocusAfterInsertPickerDismissal: FocusedField?

    init(
        designName: Binding<String>,
        primaryText: Binding<String>,
        secondaryText: Binding<String>,
        matchedSetEnabled: Bool,
        editingFamilyLabel: String,
        isProUnlocked: Bool,
        onOpenVariables: (() -> Void)? = nil
    ) {
        self._designName = designName
        self._primaryText = primaryText
        self._secondaryText = secondaryText
        self.matchedSetEnabled = matchedSetEnabled
        self.editingFamilyLabel = editingFamilyLabel
        self.isProUnlocked = isProUnlocked
        self.onOpenVariables = onOpenVariables
    }

    private enum FocusedField: Hashable {
        case designName
        case primaryText
        case secondaryText
    }

    private enum InsertTarget: Hashable {
        case primary
        case secondary
    }

    private var editorQuickSnippetDefaults: [String] {
        [
            "{{__time}}",
            "{{__weekday}}",
            "{{__today}}",
            "{{__steps_today|--|number:0}}",
            "{{__activity_steps_today|--|number:0}}",
            "{{__weather_temp|--}}",
        ]
    }


    var body: some View {
        Section {
            TextField("Design name", text: $designName)
                .textInputAutocapitalization(.words)
                .accessibilityIdentifier("EditorTextField.DesignName")
                .focused($focusedField, equals: .designName)

            variableTextFieldRow(
                title: "Primary text",
                text: $primaryText,
                focusedFieldValue: .primaryText,
                insertTarget: .primary,
                insertionRequest: $primaryInsertionRequest,
                accessibilityID: "EditorTextField.PrimaryText"
            )

            if focusedField == .primaryText {
                WidgetWeaverVariableSnippetChipsRow(
                    isProUnlocked: isProUnlocked,
                    defaults: editorQuickSnippetDefaults,
                    onInsert: { snippet in
                        insertSnippetFromChips(snippet, target: .primaryText)
                    },
                    onOpenPicker: {
                        openInsertPickerForFocusedField()
                    }
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("EditorTextField.QuickInserts.Primary")
            }

            templateFeedbackRows(for: primaryText, fieldID: "PrimaryText")

            variableTextFieldRow(
                title: "Secondary text (optional)",
                text: $secondaryText,
                focusedFieldValue: .secondaryText,
                insertTarget: .secondary,
                insertionRequest: $secondaryInsertionRequest,
                accessibilityID: "EditorTextField.SecondaryText"
            )

            if focusedField == .secondaryText {
                WidgetWeaverVariableSnippetChipsRow(
                    isProUnlocked: isProUnlocked,
                    defaults: editorQuickSnippetDefaults,
                    onInsert: { snippet in
                        insertSnippetFromChips(snippet, target: .secondaryText)
                    },
                    onOpenPicker: {
                        openInsertPickerForFocusedField()
                    }
                )
                .listRowInsets(EdgeInsets(top: 2, leading: 16, bottom: 2, trailing: 16))
                .listRowSeparator(.hidden)
                .accessibilityIdentifier("EditorTextField.QuickInserts.Secondary")
            }

            templateFeedbackRows(for: secondaryText, fieldID: "SecondaryText")

            if matchedSetEnabled {
                Text("Text fields are currently editing: \(editingFamilyLabel)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } header: {
            sectionHeader("Text")
        } footer: {
            Text("Tap \(Image(systemName: "curlybraces.square")) to insert variables. Preview appears when templates are detected.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(isPresented: $showInsertPicker, onDismiss: restoreFocusAfterInsertPickerDismissalIfNeeded) {
            NavigationStack {
                WidgetWeaverVariableInsertPickerView(
                    isProUnlocked: isProUnlocked,
                    customVariables: WidgetWeaverVariableStore.shared.loadAll(),
                    onInsert: { snippet in
                        insertSnippet(snippet)
                    }
                )
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                if focusedField == .primaryText || focusedField == .secondaryText {
                    Spacer()

                    Button {
                        openInsertPickerForFocusedField()
                    } label: {
                        Label("Insert variable", systemImage: "curlybraces.square")
                    }
                }
            }
        }
    }

    private func sectionHeader(_ title: String) -> some View {
        let headerID = "EditorSectionHeader." + title.replacingOccurrences(of: " ", with: "_")

        return Text(title)
            .font(.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .accessibilityIdentifier(headerID)
    }

    private func templateFeedbackRows(for raw: String, fieldID: String) -> some View {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)

        let hasDelimiters = trimmed.contains("{{") || trimmed.contains("}}")
        let isUnbalanced = hasDelimiters && hasUnbalancedTemplateDelimiters(trimmed)
        let isTimeDependent = hasDelimiters && !isUnbalanced && WidgetWeaverVariableTemplate.isTimeDependentTemplate(trimmed)

        let alignedStart = WidgetWeaverRenderClock.alignedTimelineStartDate(
            interval: 1.0,
            now: WidgetWeaverRenderClock.now
        )

        return Group {
            if !hasDelimiters {
                EmptyView()
            } else if isUnbalanced {
                Label("Unbalanced {{ }} delimiters", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("EditorTextField.TemplateWarning.\(fieldID)")
            } else if isTimeDependent {
                TimelineView(.periodic(from: alignedStart, by: 1.0)) { ctx in
                    templatePreviewRow(template: trimmed, now: ctx.date, fieldID: fieldID)
                }

                templateDiagnosticsRows(template: trimmed, fieldID: fieldID)
            } else {
                templatePreviewRow(template: trimmed, now: WidgetWeaverRenderClock.now, fieldID: fieldID)

                templateDiagnosticsRows(template: trimmed, fieldID: fieldID)
            }
        }
    }

    private func templateDiagnosticsRows(template: String, fieldID: String) -> some View {
        let builtInValues = TemplateKeyDiagnostics.currentBuiltInValues(now: WidgetWeaverRenderClock.now)

        let customKeys: Set<String> = {
            let vars = WidgetWeaverVariableStore.shared.loadAll()
            return Set(vars.keys.map { WidgetWeaverVariableStore.canonicalKey($0) })
        }()

        let report = TemplateKeyDiagnostics.report(
            template: template,
            isProUnlocked: isProUnlocked,
            customKeys: customKeys,
            builtInKeys: Set(builtInValues.keys)
        )

        return Group {
            if report.missingCustomKeys.count > 0 {
                Label("Missing custom keys: \(report.missingCustomKeys.joined(separator: ", "))", systemImage: "key.slash")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("EditorTextField.TemplateMissingCustomKeys.\(fieldID)")
            }

            if report.unknownKeys.count > 0 {
                Label("Unknown keys: \(report.unknownKeys.joined(separator: ", "))", systemImage: "questionmark.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("EditorTextField.TemplateUnknownKeys.\(fieldID)")
            }

            if report.usesBuiltIns && !report.builtInKeysUsed.isEmpty {
                Label("Built-ins: \(report.builtInKeysUsed.sorted().joined(separator: ", "))", systemImage: "curlybraces.square")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("EditorTextField.TemplateBuiltIns.\(fieldID)")
            }

            if report.isProLocked && report.usesCustomKeys {
                Button {
                    onOpenVariables?()
                } label: {
                    Label("Custom variables are Pro. Open Variables", systemImage: "sparkles")
                }
                .font(.caption)
                .accessibilityIdentifier("EditorTextField.TemplateProPrompt.\(fieldID)")
            }
        }
    }

    private func templatePreviewRow(template: String, now: Date, fieldID: String) -> some View {
        let rendered = renderTemplatePreview(template, now: now)

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text("Preview")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer(minLength: 0)

            Text(rendered.isEmpty ? "—" : rendered)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .lineLimit(3)
        }
        .contextMenu {
            Button("Copy preview") {
                UIPasteboard.general.string = rendered
            }
        }
        .accessibilityIdentifier("EditorTextField.TemplatePreview.\(fieldID)")
    }

    private func variableTextFieldRow(
        title: String,
        text: Binding<String>,
        focusedFieldValue: FocusedField,
        insertTarget: InsertTarget,
        insertionRequest: Binding<WWTextInsertionRequest?>,
        accessibilityID: String
    ) -> some View {
        HStack(spacing: 10) {
            let isFocusedBinding = Binding<Bool>(
                get: { focusedField == focusedFieldValue },
                set: { newValue in
                    focusedField = newValue ? focusedFieldValue : nil
                }
            )

            WWInsertableTextField(
                placeholder: title,
                accessibilityIdentifier: accessibilityID,
                text: text,
                isFocused: isFocusedBinding,
                insertionRequest: insertionRequest
            )

            Button {
                self.insertTarget = insertTarget
                restoreFocusAfterInsertPickerDismissal = focusedFieldValue
                focusedField = nil
                showInsertPicker = true
            } label: {
                Image(systemName: "curlybraces.square")
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Insert variable")
        }
    }

    private func openInsertPickerForFocusedField() {
        switch focusedField {
        case .primaryText:
            insertTarget = .primary
            restoreFocusAfterInsertPickerDismissal = .primaryText
        case .secondaryText:
            insertTarget = .secondary
            restoreFocusAfterInsertPickerDismissal = .secondaryText
        default:
            return
        }

        focusedField = nil
        showInsertPicker = true
    }

    private func insertSnippetFromChips(_ snippet: String, target: FocusedField) {
        switch target {
        case .primaryText:
            insertTarget = .primary
            primaryInsertionRequest = WWTextInsertionRequest(snippet: snippet)

        case .secondaryText:
            insertTarget = .secondary
            secondaryInsertionRequest = WWTextInsertionRequest(snippet: snippet)

        case .designName:
            return
        }

        focusedField = target
    }

    private func insertSnippet(_ snippet: String) {
        switch insertTarget {
        case .primary:
            primaryInsertionRequest = WWTextInsertionRequest(snippet: snippet)
            restoreFocusAfterInsertPickerDismissal = .primaryText
        case .secondary:
            secondaryInsertionRequest = WWTextInsertionRequest(snippet: snippet)
            restoreFocusAfterInsertPickerDismissal = .secondaryText
        }
    }

    private func restoreFocusAfterInsertPickerDismissalIfNeeded() {
        if let restore = restoreFocusAfterInsertPickerDismissal {
            focusedField = restore
        }
        restoreFocusAfterInsertPickerDismissal = nil
    }

    private func renderTemplatePreview(_ template: String, now: Date) -> String {
        var vars: [String: String] = [:]

        if isProUnlocked {
            vars = WidgetWeaverVariableStore.shared.loadAll()
        }

        let builtIns = WidgetWeaverVariableTemplate.builtInVariables(now: now)
        for (k, v) in builtIns where vars[k] == nil {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverWeatherStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverStepsStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        for (k, v) in WidgetWeaverActivityStore.shared.variablesDictionary(now: now) {
            vars[k] = v
        }

        return WidgetWeaverVariableTemplate.render(template, variables: vars, now: now, maxPasses: 3)
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

    // MARK: - Template diagnostics helper

    private enum TemplateKeyDiagnostics {

        struct Report {
            let usesBuiltIns: Bool
            let usesCustomKeys: Bool
            let isProLocked: Bool
            let builtInKeysUsed: Set<String>
            let missingCustomKeys: [String]
            let unknownKeys: [String]
        }

        static func currentBuiltInValues(now: Date) -> [String: String] {
            var vars = WidgetWeaverVariableTemplate.builtInVariables(now: now)
            for (k, v) in WidgetWeaverWeatherStore.shared.variablesDictionary(now: now) { vars[k] = v }
            for (k, v) in WidgetWeaverStepsStore.shared.variablesDictionary(now: now) { vars[k] = v }
            for (k, v) in WidgetWeaverActivityStore.shared.variablesDictionary(now: now) { vars[k] = v }
            return vars
        }

        static func report(
            template: String,
            isProUnlocked: Bool,
            customKeys: Set<String>,
            builtInKeys: Set<String>
        ) -> Report {
            let keys = extractedKeys(from: template)

            let builtInsUsed = keys.filter { builtInKeys.contains($0) }
            let customUsed = keys.filter { !$0.hasPrefix("__") }

            let missingCustom = customUsed
                .filter { !customKeys.contains(WidgetWeaverVariableStore.canonicalKey($0)) }
                .sorted()

            let unknown = keys
                .filter { !$0.hasPrefix("__") && !customKeys.contains(WidgetWeaverVariableStore.canonicalKey($0)) }
                .sorted()

            let usesBuiltIns = !builtInsUsed.isEmpty
            let usesCustom = !customUsed.isEmpty
            let proLocked = !isProUnlocked && usesCustom

            return Report(
                usesBuiltIns: usesBuiltIns,
                usesCustomKeys: usesCustom,
                isProLocked: proLocked,
                builtInKeysUsed: builtInsUsed,
                missingCustomKeys: missingCustom,
                unknownKeys: unknown
            )
        }

        private static func extractedKeys(from template: String) -> Set<String> {
            guard template.contains("{{") else { return [] }

            var keys: Set<String> = []
            var cursor = template.startIndex
            let end = template.endIndex

            while cursor < end {
                guard let open = template.range(of: "{{", range: cursor..<end) else { break }
                guard let close = template.range(of: "}}", range: open.upperBound..<end) else { break }

                let inner = template[open.upperBound..<close.lowerBound]
                let trimmed = inner.trimmingCharacters(in: .whitespacesAndNewlines)

                if trimmed.hasPrefix("=") {
                    cursor = close.upperBound
                    continue
                }

                let keyPart = trimmed.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false).first ?? ""
                let key = String(keyPart).trimmingCharacters(in: .whitespacesAndNewlines)
                if !key.isEmpty {
                    keys.insert(key)
                }

                cursor = close.upperBound
            }

            return keys
        }
    }
}
